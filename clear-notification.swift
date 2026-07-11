/*
 High-level execution flow:

 1. Determine whether Notification Center is already open.
 2. Open Notification Center if necessary using the Clock menu extra.
 3. Locate the Notification Center Accessibility window.
 4. Locate the Clear (×) button.
 5. Invoke "Clear All Notifications."
 6. Restore the original Notification Center state.
*/

import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

// MARK: - Generic AX Helpers

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(e, name as CFString, &value)
    return err == .success ? value : nil
}

func strAttr(_ e: AXUIElement, _ name: String) -> String? {
    attr(e, name) as? String
}

func boolAttr(_ e: AXUIElement, _ name: String) -> Bool? {
    attr(e, name) as? Bool
}

func children(_ e: AXUIElement, _ name: String) -> [AXUIElement] {
    attr(e, name) as? [AXUIElement] ?? []
}

func actions(_ e: AXUIElement) -> [String] {
    var value: CFArray?
    let err = AXUIElementCopyActionNames(e, &value)
    if err != .success { return [] }
    return (value as? [String]) ?? []
}

func describe(_ e: AXUIElement) -> String {
    let role = strAttr(e, kAXRoleAttribute) ?? "nil"
    let title = strAttr(e, kAXTitleAttribute) ?? "nil"
    let desc = strAttr(e, kAXDescriptionAttribute) ?? "nil"
    let id = strAttr(e, kAXIdentifierAttribute) ?? "nil"
    let acts = actions(e).joined(separator: ",")
    let focused = boolAttr(e, kAXFocusedAttribute).map { String($0) } ?? "nil"
    return "role=\(role) title=\(title) desc=\(desc) id=\(id) focused=\(focused) actions=[\(acts)]"
}

func waitUntil(
    timeout: TimeInterval = 1.0,
    interval: TimeInterval = 0.02,
    condition: () -> Bool
) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        if condition() {
            return true
        }

        Thread.sleep(forTimeInterval: interval)
    }

    return false
}

func press(_ e: AXUIElement) -> Bool {
    let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
    print("AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

// MARK: - AX Tree Search

func findElement(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 20,
    matches: (AXUIElement) -> Bool
) -> AXUIElement? {
    if depth > maxDepth { return nil }

    if matches(e) {
        return e
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            if let found = findElement(child, depth: depth + 1, maxDepth: maxDepth, matches: matches) {
                return found
            }
        }
    }

    return nil
}

func findMenuExtra(_ e: AXUIElement, id targetID: String, depth: Int = 0, maxDepth: Int = 8) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXIdentifierAttribute) == targetID
    }
}

func findXmark(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 20) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXRoleAttribute) == kAXMenuButtonRole as String &&
        strAttr(node, kAXIdentifierAttribute) == "xmark"
    }
}

func findClearAll(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = 20) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXRoleAttribute) == kAXMenuItemRole as String &&
        strAttr(node, kAXTitleAttribute) == "Clear All Notifications"
    }
}

// MARK: - Notification Center Detection

let notificationCenterBundleIDs = [
    "com.apple.notificationcenterui",
    "com.apple.UserNotificationCenter",
    "com.apple.notificationcenter"
]

func isNotificationCenterWindow(_ e: AXUIElement) -> Bool {
    strAttr(e, kAXRoleAttribute) == kAXWindowRole as String &&
    strAttr(e, kAXTitleAttribute) == "Notification Center"
}

// Notification Center may expose an AXWindow even when it is not visibly
// open. Through testing, AXFocused proved to be the reliable indicator
// that Notification Center is actually being presented to the user.
func isFocusedNotificationCenterWindow(_ e: AXUIElement) -> Bool {
    isNotificationCenterWindow(e) &&
    boolAttr(e, kAXFocusedAttribute) == true
}

func axWindows(for app: NSRunningApplication) -> [AXUIElement] {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    return children(axApp, kAXWindowsAttribute)
}

func notificationCenterApplications() -> [NSRunningApplication] {
    notificationCenterBundleIDs.flatMap { bundleID in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }
}

func notificationCenterWindows(logFound: Bool = true) -> [AXUIElement] {
    var windows: [AXUIElement] = []

    for app in notificationCenterApplications() {
        let matchingWindows = axWindows(for: app).filter(isNotificationCenterWindow)

        if logFound && !matchingWindows.isEmpty {
            print("FOUND NOTIFICATION CENTER APP: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")
        }

        windows.append(contentsOf: matchingWindows)
    }

    return windows
}

func focusedNotificationCenterWindow(logFound: Bool = true) -> AXUIElement? {
    notificationCenterWindows(logFound: logFound).first { window in
        boolAttr(window, kAXFocusedAttribute) == true
    }
}

func isNotificationCenterOpen() -> Bool {
    focusedNotificationCenterWindow(logFound: false) != nil
}

func waitForNotificationCenterWindow() -> AXUIElement? {
    var window: AXUIElement?

    let found = waitUntil(timeout: 1.0, interval: 0.02) {
        window = focusedNotificationCenterWindow(logFound: false)
        return window != nil
    }

    if found {
        return focusedNotificationCenterWindow(logFound: true) ?? window
    }

    return nil
}

// MARK: - Notification Center Actions

func pressClockMenuExtra(label: String) -> Bool {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
        .first else {
        print("ControlCenter not found")
        return false
    }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)

    guard let clock = findMenuExtra(axApp, id: "com.apple.menuextra.clock") else {
        print("Clock menu extra not found")
        return false
    }

    print("FOUND CLOCK:", describe(clock))

    let err = AXUIElementPerformAction(clock, kAXPressAction as CFString)
    print("\(label) Clock AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

func openNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Open")
}

func closeNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Close")
}

func closeNotificationCenterIfNeeded(wasInitiallyOpen: Bool) {
    if wasInitiallyOpen {
        print("Leaving Notification Center open because it was already open")
        return
    }

    if !isNotificationCenterOpen() {
        print("Notification Center already closed")
        return
    }

    _ = closeNotificationCenterViaAX()
}

// MARK: - Notification Clearing

func waitForClearAll(in window: AXUIElement) -> AXUIElement? {
    var item: AXUIElement?

    let found = waitUntil(timeout: 1.0, interval: 0.02) {
        item = findClearAll(window)
        return item != nil
    }

    return found ? item : nil
}

// MARK: - Diagnostics

func dumpLikelySystemWindows() {
    print("DEBUG: AX windows from Notification Center candidate apps:")

    for app in notificationCenterApplications() {
        let windows = axWindows(for: app)

        if windows.isEmpty {
            print("  app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) windows=[]")
        } else {
            for window in windows {
                print("  app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) window=\(describe(window))")
            }
        }
    }
}

// MARK: - Main

print("AX trusted: \(AXIsProcessTrusted())")

let wasInitiallyOpen = isNotificationCenterOpen()
print("Notification Center initially open: \(wasInitiallyOpen)")

if !wasInitiallyOpen {
    guard openNotificationCenterViaAX() else {
        print("Could not open Notification Center")
        exit(1)
    }
}

guard let window = waitForNotificationCenterWindow() else {
    print("Notification Center window not found or not focused")
    dumpLikelySystemWindows()
    exit(1)
}

print("WINDOW:", describe(window))

guard let xmark = findXmark(window) else {
    print("Nothing to clear: xmark button not found")
    closeNotificationCenterIfNeeded(wasInitiallyOpen: wasInitiallyOpen)
    print("SUCCESS")
    exit(0)
}

print("FOUND XMARK:", describe(xmark))

let showErr = AXUIElementPerformAction(xmark, kAXShowMenuAction as CFString)
print("AXShowMenu result: \(showErr.rawValue) \(showErr)")

guard let clearItem = waitForClearAll(in: window) else {
    print("Nothing to clear: Clear All Notifications menu item not found")
    closeNotificationCenterIfNeeded(wasInitiallyOpen: wasInitiallyOpen)
    print("SUCCESS")
    exit(0)
}

print("FOUND CLEAR ITEM:", describe(clearItem))

if press(clearItem) {
    closeNotificationCenterIfNeeded(wasInitiallyOpen: wasInitiallyOpen)
    print("SUCCESS")
    exit(0)
}

print("PRESS FAILED")
exit(1)

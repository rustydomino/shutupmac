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

// MARK: - Configuration

let controlCenterBundleID = "com.apple.controlcenter"

let notificationCenterBundleIDs = [
    "com.apple.notificationcenterui",
    "com.apple.UserNotificationCenter",
    "com.apple.notificationcenter"
]

let notificationCenterWindowTitle = "Notification Center"
let clockMenuExtraIdentifier = "com.apple.menuextra.clock"
let clearButtonIdentifier = "xmark"
let clearAllMenuItemTitle = "Clear All Notifications"

let defaultPollingTimeout: TimeInterval = 1.0
let defaultPollingInterval: TimeInterval = 0.02

let defaultAXTreeSearchMaxDepth = 20
let menuExtraSearchMaxDepth = 8

// MARK: - Debug Logging

let DEBUG_LOGGING = true

/// Emits developer-facing diagnostic output when debug logging is enabled.
///
/// The message is autoclosured so expensive string interpolation, including
/// Accessibility tree descriptions, is skipped when debug logging is disabled.
func debugLog(_ message: @autoclosure () -> String) {
    guard DEBUG_LOGGING else { return }
    print(message())
}

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
    timeout: TimeInterval = defaultPollingTimeout,
    interval: TimeInterval = defaultPollingInterval,
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
    debugLog("AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

// MARK: - AX Tree Search

/// Performs a depth-limited search through an Accessibility tree.
///
/// The search checks common child collections used by macOS Accessibility APIs,
/// including visible children and navigation-order children.
func findElement(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = defaultAXTreeSearchMaxDepth,
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

func findMenuExtra(_ e: AXUIElement, id targetID: String, depth: Int = 0, maxDepth: Int = menuExtraSearchMaxDepth) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXIdentifierAttribute) == targetID
    }
}

func findXmark(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = defaultAXTreeSearchMaxDepth) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXRoleAttribute) == kAXMenuButtonRole as String &&
        strAttr(node, kAXIdentifierAttribute) == clearButtonIdentifier
    }
}

func findClearAll(_ e: AXUIElement, depth: Int = 0, maxDepth: Int = defaultAXTreeSearchMaxDepth) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXRoleAttribute) == kAXMenuItemRole as String &&
        strAttr(node, kAXTitleAttribute) == clearAllMenuItemTitle
    }
}

// MARK: - Notification Center Detection

func isNotificationCenterWindow(_ e: AXUIElement) -> Bool {
    strAttr(e, kAXRoleAttribute) == kAXWindowRole as String &&
    strAttr(e, kAXTitleAttribute) == notificationCenterWindowTitle
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

/// Returns running applications that may host Notification Center UI.
///
/// macOS has used multiple bundle identifiers for Notification Center across
/// releases, so callers should search all known candidates rather than relying
/// on a single bundle identifier.
func notificationCenterApplications() -> [NSRunningApplication] {
    notificationCenterBundleIDs.flatMap { bundleID in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }
}

/// Returns all Accessibility windows that appear to be Notification Center windows.
///
/// This is the shared discovery point for Notification Center window lookup.
/// More specific helpers should filter this result rather than duplicating
/// bundle/application/window traversal.
func notificationCenterWindows(logFound: Bool = true) -> [AXUIElement] {
    var windows: [AXUIElement] = []

    for app in notificationCenterApplications() {
        let matchingWindows = axWindows(for: app).filter(isNotificationCenterWindow)

        if logFound && !matchingWindows.isEmpty {
            debugLog("FOUND NOTIFICATION CENTER APP: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")
        }

        windows.append(contentsOf: matchingWindows)
    }

    return windows
}

/// Returns the Notification Center window that is currently presented to the user.
///
/// This intentionally filters the general Notification Center window list by
/// focus state instead of treating window existence alone as visibility.
func focusedNotificationCenterWindow(logFound: Bool = true) -> AXUIElement? {
    notificationCenterWindows(logFound: logFound).first { window in
        boolAttr(window, kAXFocusedAttribute) == true
    }
}

/// Returns true when Notification Center appears to be visibly open.
func isNotificationCenterOpen() -> Bool {
    focusedNotificationCenterWindow(logFound: false) != nil
}

/// Waits briefly for the focused Notification Center window to appear.
///
/// Opening Notification Center through the menu extra is asynchronous, so the
/// AX window may not be available immediately after pressing the Clock item.
func waitForNotificationCenterWindow() -> AXUIElement? {
    var window: AXUIElement?

    let found = waitUntil(timeout: defaultPollingTimeout, interval: defaultPollingInterval) {
        window = focusedNotificationCenterWindow(logFound: false)
        return window != nil
    }

    if found {
        return focusedNotificationCenterWindow(logFound: true) ?? window
    }

    return nil
}

// MARK: - Notification Center Actions

/// Presses the Clock menu extra, which toggles Notification Center.
///
/// Notification Center does not expose a simple public API for opening and
/// closing, so this uses the Accessibility representation of the menu bar Clock.
func pressClockMenuExtra(label: String) -> Bool {
    guard let app = NSRunningApplication
        .runningApplications(withBundleIdentifier: controlCenterBundleID)
        .first else {
        print("ControlCenter not found")
        return false
    }

    let axApp = AXUIElementCreateApplication(app.processIdentifier)

    guard let clock = findMenuExtra(axApp, id: clockMenuExtraIdentifier) else {
        print("Clock menu extra not found")
        return false
    }

    debugLog("FOUND CLOCK: \(describe(clock))")

    let err = AXUIElementPerformAction(clock, kAXPressAction as CFString)
    debugLog("\(label) Clock AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

func openNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Open")
}

func closeNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Close")
}

/// Restores Notification Center to its original open/closed state.
///
/// If Notification Center was already open when the program started, it is left
/// open. Otherwise, it is closed after clearing is complete.
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

/// Waits briefly for the Clear All Notifications menu item to appear.
///
/// The item is created only after the Clear button menu is shown, so lookup must
/// poll for a short period instead of assuming it is immediately available.
func waitForClearAll(in window: AXUIElement) -> AXUIElement? {
    var item: AXUIElement?

    let found = waitUntil(timeout: defaultPollingTimeout, interval: defaultPollingInterval) {
        item = findClearAll(window)
        return item != nil
    }

    return found ? item : nil
}

// MARK: - Diagnostics

/// Dumps candidate Notification Center Accessibility windows for troubleshooting.
///
/// This is only useful when window discovery fails, especially after macOS UI or
/// Accessibility behavior changes.
func dumpLikelySystemWindows() {
    debugLog("DEBUG: AX windows from Notification Center candidate apps:")

    for app in notificationCenterApplications() {
        let windows = axWindows(for: app)

        if windows.isEmpty {
            debugLog("  app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) windows=[]")
        } else {
            for window in windows {
                debugLog("  app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) window=\(describe(window))")
            }
        }
    }
}

// MARK: - Main

debugLog("AX trusted: \(AXIsProcessTrusted())")

let wasInitiallyOpen = isNotificationCenterOpen()
debugLog("Notification Center initially open: \(wasInitiallyOpen)")

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

debugLog("WINDOW: \(describe(window))")

guard let xmark = findXmark(window) else {
    print("Nothing to clear: xmark button not found")
    closeNotificationCenterIfNeeded(wasInitiallyOpen: wasInitiallyOpen)
    print("SUCCESS")
    exit(0)
}

debugLog("FOUND XMARK: \(describe(xmark))")

let showErr = AXUIElementPerformAction(xmark, kAXShowMenuAction as CFString)
debugLog("AXShowMenu result: \(showErr.rawValue) \(showErr)")

guard let clearItem = waitForClearAll(in: window) else {
    print("Nothing to clear: Clear All Notifications menu item not found")
    closeNotificationCenterIfNeeded(wasInitiallyOpen: wasInitiallyOpen)
    print("SUCCESS")
    exit(0)
}

debugLog("FOUND CLEAR ITEM: \(describe(clearItem))")

if press(clearItem) {
    closeNotificationCenterIfNeeded(wasInitiallyOpen: wasInitiallyOpen)
    print("SUCCESS")
    exit(0)
}

print("PRESS FAILED")
exit(1)

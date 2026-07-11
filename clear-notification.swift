import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let err = AXUIElementCopyAttributeValue(e, name as CFString, &value)
    return err == .success ? value : nil
}

func strAttr(_ e: AXUIElement, _ name: String) -> String? {
    attr(e, name) as? String
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
    return "role=\(role) title=\(title) desc=\(desc) id=\(id) actions=[\(acts)]"
}

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

func findMenuExtra(_ e: AXUIElement, id targetID: String, depth: Int = 0, maxDepth: Int = 8) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXIdentifierAttribute) == targetID
    }
}

func press(_ e: AXUIElement) -> Bool {
    let err = AXUIElementPerformAction(e, kAXPressAction as CFString)
    print("AXPress result: \(err.rawValue) \(err)")
    return err == .success
}

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

func isNotificationCenterWindow(_ e: AXUIElement) -> Bool {
    strAttr(e, kAXRoleAttribute) == kAXWindowRole as String &&
    strAttr(e, kAXTitleAttribute) == "Notification Center"
}

func axWindows(for app: NSRunningApplication) -> [AXUIElement] {
    let axApp = AXUIElementCreateApplication(app.processIdentifier)

    var windows = children(axApp, kAXWindowsAttribute)

    // Some system UI processes do not expose everything through AXWindows.
    // Search the app subtree as a fallback, but still avoid screen-coordinate hit tests.
    if let found = findElement(axApp, maxDepth: 10, matches: isNotificationCenterWindow),
       !windows.contains(where: { CFEqual($0, found) }) {
        windows.append(found)
    }

    return windows
}

func findNotificationCenterWindowInApp(_ app: NSRunningApplication) -> AXUIElement? {
    for window in axWindows(for: app) {
        if isNotificationCenterWindow(window) {
            return window
        }

        if let found = findElement(window, maxDepth: 10, matches: isNotificationCenterWindow) {
            return found
        }
    }

    return nil
}

func findNotificationCenterWindow() -> AXUIElement? {
    let workspace = NSWorkspace.shared

    // Try the most likely owning processes first. The exact process name/bundle
    // has varied across macOS releases, so keep this as a ranked list.
    let preferredBundleIDs = [
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenter",
        "com.apple.controlcenter"
    ]

    for bundleID in preferredBundleIDs {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            if let found = findNotificationCenterWindowInApp(app) {
                print("FOUND NOTIFICATION CENTER APP: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")
                return found
            }
        }
    }

    // Last resort: scan all running applications by AX window title.
    // This is still AX-only and removes the hard-coded coordinate dependency.
    for app in workspace.runningApplications {
        if let found = findNotificationCenterWindowInApp(app) {
            print("FOUND NOTIFICATION CENTER APP BY SCAN: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")
            return found
        }
    }

    return nil
}

func waitForNotificationCenterWindow(timeout: TimeInterval = 1.0) -> AXUIElement? {
    var window: AXUIElement?

    let found = waitUntil(timeout: timeout) {
        window = findNotificationCenterWindow()
        return window != nil
    }

    return found ? window : nil
}

func waitForClearAll(in window: AXUIElement, timeout: TimeInterval = 1.0) -> AXUIElement? {
    var clearItem: AXUIElement?

    let found = waitUntil(timeout: timeout) {
        clearItem = findClearAll(window)
        return clearItem != nil
    }

    return found ? clearItem : nil
}


func dumpLikelySystemWindows() {
    print("DEBUG: visible AX windows with titles from likely system UI apps:")

    for app in NSWorkspace.shared.runningApplications {
        let name = app.localizedName ?? ""
        let bundle = app.bundleIdentifier ?? ""

        if !(name.localizedCaseInsensitiveContains("Notification") ||
             name.localizedCaseInsensitiveContains("Control") ||
             bundle.localizedCaseInsensitiveContains("notification") ||
             bundle.localizedCaseInsensitiveContains("controlcenter")) {
            continue
        }

        let windows = axWindows(for: app)
        if windows.isEmpty {
            print("  app bundle=\(bundle) name=\(name) pid=\(app.processIdentifier) windows=[]")
        } else {
            for window in windows {
                print("  app bundle=\(bundle) name=\(name) pid=\(app.processIdentifier) window=\(describe(window))")
            }
        }
    }
}

print("AX trusted: \(AXIsProcessTrusted())")

guard openNotificationCenterViaAX() else {
    print("Could not open Notification Center")
    exit(1)
}

guard let window = waitForNotificationCenterWindow() else {
    print("Notification Center window not found")
    dumpLikelySystemWindows()
    exit(1)
}

print("WINDOW:", describe(window))

guard let xmark = findXmark(window) else {
    print("XMARK NOT FOUND")
    exit(1)
}

print("FOUND XMARK:", describe(xmark))

let showErr = AXUIElementPerformAction(xmark, kAXShowMenuAction as CFString)
print("AXShowMenu result: \(showErr.rawValue) \(showErr)")

guard let clearItem = waitForClearAll(in: window) else {
    print("CLEAR ITEM NOT FOUND")
    exit(1)
}

print("FOUND CLEAR ITEM:", describe(clearItem))

if press(clearItem) {
    guard closeNotificationCenterViaAX() else {
        print("Notifications cleared, but could not close Notification Center")
        exit(1)
    }

    print("SUCCESS")
    exit(0)
}

print("PRESS FAILED")
exit(1)

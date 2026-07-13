/*
 High-level execution flow:

 1. Determine whether the actual Notification Center panel is already open.
 2. Open Notification Center if necessary using the Clock menu extra.
 3. Locate the Notification Center Accessibility window.
 4. Locate the Clear (x) button.
 5. Invoke "Clear All Notifications."
 6. Ensure Notification Center is closed afterward.

 This version is refactored so the core behavior is callable from either:
 - the command-line executable, or
 - the macOS menu bar app.
*/

import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

// MARK: - Configuration

enum Config {
    static let systemUIServerBundleID = "com.apple.systemuiserver"
    static let controlCenterBundleID = "com.apple.controlcenter"

    static let notificationCenterBundleIDs = [
        "com.apple.notificationcenterui",
        "com.apple.UserNotificationCenter",
        "com.apple.notificationcenter"
    ]

    static let notificationCenterWindowTitle = "Notification Center"
    static let clockMenuExtraIdentifier = "com.apple.menuextra.clock"
    static let clearButtonIdentifier = "xmark"
    static let clearAllMenuItemTitle = "Clear All Notifications"

    // Open-panel markers found through AX tree testing.
    // A notification banner can create a Notification Center AXWindow even when
    // the actual panel is closed, so window existence alone is not reliable.
    static let widgetEditorButtonIdentifier = "widget-editor-button"
    static let widgetGridSubrole = "AXOpaqueProviderGrid"

    static let defaultPollingTimeout: TimeInterval = 1.0
    static let defaultPollingInterval: TimeInterval = 0.02

    static let defaultAXTreeSearchMaxDepth = 20
    static let menuExtraSearchMaxDepth = 8

    static let notificationCenterCloseRetries = 3
    static let notificationCenterCloseRetryDelay: TimeInterval = 0.15
}

// MARK: - Debug Logging

enum Debug {
#if DEBUG
    static var isEnabled = true
#else
    static var isEnabled = false
#endif
}

/// Emits developer-facing diagnostic output when debug logging is enabled.
///
/// The message is autoclosured so expensive string interpolation, including
/// Accessibility tree descriptions, is skipped when debug logging is disabled.
func debugLog(_ message: @autoclosure () -> String) {
    guard Debug.isEnabled else { return }
    fputs(message() + "\n", stderr)
}

// MARK: - Result Model

/// The result of one attempt to clear Notification Center.
///
/// The CLI uses this to decide which message to print and which exit code to
/// return. The GUI app can use the same result to update menu text, show a
/// status message, or display an error without duplicating the clearing logic.
struct ClearNotificationsResult {
    let succeeded: Bool
    let didClear: Bool
    let message: String
    let exitCode: Int32

    static func success(_ message: String, didClear: Bool) -> ClearNotificationsResult {
        ClearNotificationsResult(
            succeeded: true,
            didClear: didClear,
            message: message,
            exitCode: 0
        )
    }

    static func failure(_ message: String) -> ClearNotificationsResult {
        ClearNotificationsResult(
            succeeded: false,
            didClear: false,
            message: message,
            exitCode: 1
        )
    }
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
    timeout: TimeInterval = Config.defaultPollingTimeout,
    interval: TimeInterval = Config.defaultPollingInterval,
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
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
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

func findClockMenuExtra(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth
) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        let role = strAttr(node, kAXRoleAttribute) ?? ""
        let title = strAttr(node, kAXTitleAttribute) ?? ""
        let desc = strAttr(node, kAXDescriptionAttribute) ?? ""
        let id = strAttr(node, kAXIdentifierAttribute) ?? ""

        let looksLikeClock =
            id == Config.clockMenuExtraIdentifier ||
            title.localizedCaseInsensitiveContains("clock") ||
            desc.localizedCaseInsensitiveContains("clock") ||
            title.localizedCaseInsensitiveContains("date") ||
            desc.localizedCaseInsensitiveContains("date")

        let isPressable =
            actions(node).contains(kAXPressAction as String)

        let isMenuBarThing =
            role == kAXMenuBarItemRole as String ||
            role == kAXButtonRole as String

        return looksLikeClock && isPressable && isMenuBarThing
    }
}

func findXmark(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth
) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXRoleAttribute) == kAXMenuButtonRole as String &&
        strAttr(node, kAXIdentifierAttribute) == Config.clearButtonIdentifier
    }
}

func findClearAll(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth
) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        strAttr(node, kAXRoleAttribute) == kAXMenuItemRole as String &&
        strAttr(node, kAXTitleAttribute) == Config.clearAllMenuItemTitle
    }
}

// MARK: - Notification Center Detection

func isNotificationCenterWindow(_ e: AXUIElement) -> Bool {
    strAttr(e, kAXRoleAttribute) == kAXWindowRole as String &&
    strAttr(e, kAXTitleAttribute) == Config.notificationCenterWindowTitle
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
    Config.notificationCenterBundleIDs.flatMap { bundleID in
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    }
}

/// Returns all Accessibility windows that appear to be Notification Center windows.
///
/// Important: the presence of a Notification Center AXWindow does not always mean
/// Notification Center is actually open. A visible notification banner can also
/// create a full-screen Notification Center AXWindow. Callers that need to know
/// whether the actual Notification Center panel is open should use
/// notificationCenterOpenPanelWindow().
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

/// Returns true when a node appears to be part of the actual open Notification Center panel.
///
/// Testing showed that a notification banner can create a Notification Center AXWindow
/// even when Notification Center itself is closed. The actual open panel exposes
/// additional controls, including:
///
/// - the Clear Notifications menu button with identifier "xmark"
/// - the Edit Widgets button with identifier "widget-editor-button"
/// - the widget grid with subrole "AXOpaqueProviderGrid"
func isNotificationCenterOpenPanelMarker(_ e: AXUIElement) -> Bool {
    let id = strAttr(e, kAXIdentifierAttribute) ?? ""
    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""

    if id == Config.clearButtonIdentifier {
        return true
    }

    if id == Config.widgetEditorButtonIdentifier {
        return true
    }

    if subrole == Config.widgetGridSubrole {
        return true
    }

    return false
}

/// Returns true when this Notification Center AXWindow contains controls that only
/// appear when the full Notification Center panel is actually open.
func isNotificationCenterOpenPanelWindow(_ window: AXUIElement) -> Bool {
    findElement(window, maxDepth: Config.defaultAXTreeSearchMaxDepth) { node in
        isNotificationCenterOpenPanelMarker(node)
    } != nil
}

/// Returns the Notification Center window only if the actual panel appears open.
///
/// This is stricter than checking for the Notification Center AXWindow alone.
/// It avoids false positives caused by ordinary notification banners.
func notificationCenterOpenPanelWindow(logFound: Bool = true) -> AXUIElement? {
    for window in notificationCenterWindows(logFound: logFound) {
        if isNotificationCenterOpenPanelWindow(window) {
            debugLog("FOUND OPEN NOTIFICATION CENTER PANEL: \(describe(window))")
            return window
        }
    }

    return nil
}

/// Returns true when the actual Notification Center panel appears to be visibly open.
func isNotificationCenterOpen() -> Bool {
    notificationCenterOpenPanelWindow(logFound: false) != nil
}

/// Waits briefly for the actual Notification Center panel to appear.
///
/// Opening Notification Center through the menu extra is asynchronous, so the
/// open-panel controls may not be available immediately after pressing the Clock item.
func waitForNotificationCenterOpenPanelWindow() -> AXUIElement? {
    var panelWindow: AXUIElement?

    let found = waitUntil(timeout: Config.defaultPollingTimeout, interval: Config.defaultPollingInterval) {
        panelWindow = notificationCenterOpenPanelWindow(logFound: false)
        return panelWindow != nil
    }

    guard found, let panelWindow else {
        return nil
    }

    debugLog("FOUND NOTIFICATION CENTER OPEN PANEL WINDOW: \(describe(panelWindow))")

    if actions(panelWindow).contains(kAXRaiseAction as String) {
        let raiseErr = AXUIElementPerformAction(panelWindow, kAXRaiseAction as CFString)
        debugLog("Notification Center AXRaise result: \(raiseErr.rawValue) \(raiseErr)")
    }

    return panelWindow
}

// MARK: - Notification Center Actions

/// Presses the Clock menu extra, which toggles Notification Center.
///
/// Notification Center does not expose a simple public API for opening and
/// closing, so this uses the Accessibility representation of the menu bar Clock.
func pressClockMenuExtra(label: String) -> Bool {
    let candidateBundleIDs = [
        Config.controlCenterBundleID,
        Config.systemUIServerBundleID
    ]

    for bundleID in candidateBundleIDs {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)

        for app in apps {
            debugLog("Searching for Clock in app: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")

            let axApp = AXUIElementCreateApplication(app.processIdentifier)

            if let clock = findClockMenuExtra(axApp) {
                debugLog("FOUND CLOCK: \(describe(clock))")

                let err = AXUIElementPerformAction(clock, kAXPressAction as CFString)
                debugLog("\(label) Clock AXPress result: \(err.rawValue) \(err)")

                return err == .success
            }

            debugLog("Clock not found in \(app.bundleIdentifier ?? "nil")")
        }
    }

    print("Clock menu extra not found")
    return false
}

func openNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Open")
}

func closeNotificationCenterViaAX() -> Bool {
    pressClockMenuExtra(label: "Close")
}

/// Ensures the actual Notification Center panel is open.
///
/// The Clock menu extra is a toggle, so this function first checks whether the
/// open panel is already present. It only presses the Clock item if the panel
/// does not appear to be open.
func ensureNotificationCenterOpen() -> AXUIElement? {
    if let existingWindow = notificationCenterOpenPanelWindow(logFound: false) {
        debugLog("Notification Center panel already open")
        return existingWindow
    }

    debugLog("Notification Center panel not open; pressing Clock to open")

    guard openNotificationCenterViaAX() else {
        return nil
    }

    return waitForNotificationCenterOpenPanelWindow()
}

/// Ensures the actual Notification Center panel is closed.
///
/// The Clock menu extra is a toggle, so this function checks the panel state
/// after pressing and retries if necessary.
func ensureNotificationCenterClosed() {
    for attempt in 1...Config.notificationCenterCloseRetries {
        if !isNotificationCenterOpen() {
            debugLog("Notification Center panel is closed")
            return
        }

        debugLog("Notification Center panel still open; close attempt \(attempt)")

        _ = closeNotificationCenterViaAX()

        let closed = waitUntil(timeout: 0.75, interval: Config.defaultPollingInterval) {
            !isNotificationCenterOpen()
        }

        if closed {
            debugLog("Notification Center panel closed")
            return
        }

        Thread.sleep(forTimeInterval: Config.notificationCenterCloseRetryDelay)
    }

    debugLog("Notification Center panel still appears open after close retries")
}

// MARK: - Notification Clearing

/// Waits briefly for the Clear All Notifications menu item to appear.
///
/// The item is created only after the Clear button menu is shown, so lookup must
/// poll for a short period instead of assuming it is immediately available.
func waitForClearAll(in window: AXUIElement) -> AXUIElement? {
    var item: AXUIElement?

    let found = waitUntil(timeout: Config.defaultPollingTimeout, interval: Config.defaultPollingInterval) {
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
func dumpInterestingAXTree(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 6,
    maxNodes: Int = 200,
    counter: inout Int
) {
    if depth > maxDepth { return }
    if counter >= maxNodes { return }

    counter += 1

    let role = strAttr(e, kAXRoleAttribute) ?? ""
    let title = strAttr(e, kAXTitleAttribute) ?? ""
    let desc = strAttr(e, kAXDescriptionAttribute) ?? ""
    let id = strAttr(e, kAXIdentifierAttribute) ?? ""
    let acts = actions(e)

    let hasInterestingText =
        !title.isEmpty ||
        !desc.isEmpty ||
        !id.isEmpty ||
        !acts.isEmpty ||
        role.localizedCaseInsensitiveContains("menu") ||
        role.localizedCaseInsensitiveContains("button")

    if hasInterestingText {
        let indent = String(repeating: "  ", count: depth)
        debugLog("\(indent)\(describe(e))")
    }

    for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            dumpInterestingAXTree(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                counter: &counter
            )
        }
    }
}

func dumpAXTreeForClockSearch(app: NSRunningApplication) {
    debugLog("DEBUG: AX tree for app bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier)")

    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var counter = 0

    dumpInterestingAXTree(
        axApp,
        maxDepth: 8,
        maxNodes: 300,
        counter: &counter
    )

    debugLog("DEBUG: dumped \(counter) AX nodes")
}

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

// MARK: - Callable Engine

/// Public-facing clearing engine.
///
/// This is the important refactor: the full notification-clearing workflow now
/// lives inside one callable function. The CLI can call this function, and the
/// menu bar app can call the same function from a button or menu item.
enum ShutUpMac {
    static func clearNotifications() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        guard let window = ensureNotificationCenterOpen() else {
            dumpLikelySystemWindows()
            return .failure("Could not open Notification Center")
        }

        debugLog("WINDOW: \(describe(window))")

        guard let xmark = findXmark(window) else {
            ensureNotificationCenterClosed()
            return .success("Nothing to clear: xmark button not found", didClear: false)
        }

        debugLog("FOUND XMARK: \(describe(xmark))")

        let showErr = AXUIElementPerformAction(xmark, kAXShowMenuAction as CFString)
        debugLog("AXShowMenu result: \(showErr.rawValue) \(showErr)")

        guard let clearItem = waitForClearAll(in: window) else {
            ensureNotificationCenterClosed()
            return .success("Nothing to clear: Clear All Notifications menu item not found", didClear: false)
        }

        debugLog("FOUND CLEAR ITEM: \(describe(clearItem))")

        if press(clearItem) {
            ensureNotificationCenterClosed()
            return .success("SUCCESS", didClear: true)
        }

        ensureNotificationCenterClosed()
        return .failure("PRESS FAILED")
    }
}

// MARK: - CLI Entry Point

/// Thin command-line wrapper.
///
/// This keeps the current CLI behavior intact while ensuring the actual clearing
/// implementation is callable from somewhere else later.

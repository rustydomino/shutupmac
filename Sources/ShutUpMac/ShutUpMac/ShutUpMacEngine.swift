/*
 High-level execution flow:

 1. Keep the existing nuclear clear-all path:
    - Determine whether the actual Notification Center panel is already open.
    - Open Notification Center if necessary using the Clock menu extra.
    - Locate the Notification Center Accessibility window.
    - Locate the Clear (x) button.
    - Invoke "Clear All Notifications."
    - Ensure Notification Center is closed afterward.

 2. Add bare-bones visible-notification actions:
    - closeTopVisibleNotification(): find the top visible single alert and run Name:Close.
    - clearTopVisibleStack(): find the top visible stack and run Name:Clear All.

 The nuclear path is intentionally separate from the newer targeted actions.
 The targeted actions do not expand stacks, do not close single notifications when
 asked to clear a stack, and do not open/close Notification Center.
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

    static let notificationAlertSubrole = "AXNotificationCenterAlert"
    static let notificationAlertStackSubrole = "AXNotificationCenterAlertStack"
    static let notificationCloseActionNameFragment = "Close"
    static let notificationClearAllActionNameFragment = "Clear All"

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

/// The result of one notification operation.
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

func cgPointAttr(_ e: AXUIElement, _ name: String) -> CGPoint? {
    guard let value = attr(e, name) else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgPoint else { return nil }

    var point = CGPoint.zero
    guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
    return point
}

func cgSizeAttr(_ e: AXUIElement, _ name: String) -> CGSize? {
    guard let value = attr(e, name) else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

    let axValue = value as! AXValue
    guard AXValueGetType(axValue) == .cgSize else { return nil }

    var size = CGSize.zero
    guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
    return size
}

func frameAttr(_ e: AXUIElement) -> CGRect? {
    guard let position = cgPointAttr(e, kAXPositionAttribute) else { return nil }
    guard let size = cgSizeAttr(e, kAXSizeAttribute) else { return nil }
    return CGRect(origin: position, size: size)
}

func roundedFrameKey(_ rect: CGRect) -> String {
    let x = Int(rect.origin.x.rounded())
    let y = Int(rect.origin.y.rounded())
    let w = Int(rect.size.width.rounded())
    let h = Int(rect.size.height.rounded())
    return "x\(x)-y\(y)-w\(w)-h\(h)"
}

func formatFrame(_ rect: CGRect) -> String {
    String(
        format: "x=%.0f y=%.0f w=%.0f h=%.0f",
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height
    )
}

func describe(_ e: AXUIElement) -> String {
    let role = strAttr(e, kAXRoleAttribute) ?? "nil"
    let subrole = strAttr(e, kAXSubroleAttribute) ?? "nil"
    let title = strAttr(e, kAXTitleAttribute) ?? "nil"
    let desc = strAttr(e, kAXDescriptionAttribute) ?? "nil"
    let id = strAttr(e, kAXIdentifierAttribute) ?? "nil"
    let acts = actions(e).joined(separator: ",")
    let focused = boolAttr(e, kAXFocusedAttribute).map { String($0) } ?? "nil"

    let frameDescription: String
    if let frame = frameAttr(e) {
        frameDescription = formatFrame(frame)
    } else {
        frameDescription = "nil"
    }

    return "role=\(role) subrole=\(subrole) title=\(title) desc=\(desc) id=\(id) focused=\(focused) frame=\(frameDescription) actions=[\(acts)]"
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

func performAction(_ actionName: String, on e: AXUIElement) -> Bool {
    let err = AXUIElementPerformAction(e, actionName as CFString)
    debugLog("AX action \(actionName) result: \(err.rawValue) \(err)")
    return err == .success
}

func performFirstAction(on e: AXUIElement, nameContaining needle: String) -> Bool {
    guard let actionName = actions(e).first(where: { actionName in
        actionName.localizedCaseInsensitiveContains(needle)
    }) else {
        debugLog("No AX action containing \(needle) found on element: \(describe(e))")
        return false
    }

    return performAction(actionName, on: e)
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
    var seenPIDs = Set<pid_t>()
    var apps: [NSRunningApplication] = []

    for bundleID in Config.notificationCenterBundleIDs {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard !seenPIDs.contains(app.processIdentifier) else { continue }
            seenPIDs.insert(app.processIdentifier)
            apps.append(app)
        }
    }

    return apps
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

// MARK: - Visible Notification Discovery

struct VisibleNotificationCandidate {
    let element: AXUIElement
    let subrole: String
    let frame: CGRect

    var kindLabel: String {
        if subrole == Config.notificationAlertStackSubrole {
            return "stack"
        }

        if subrole == Config.notificationAlertSubrole {
            return "alert"
        }

        return subrole
    }
}

func notificationSearchRoots(logFound: Bool = true) -> [AXUIElement] {
    var roots: [AXUIElement] = []

    for app in notificationCenterApplications() {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let windows = children(axApp, kAXWindowsAttribute)
        let notificationWindows = windows.filter(isNotificationCenterWindow)

        if logFound {
            debugLog("SEARCH NOTIFICATION APP: bundle=\(app.bundleIdentifier ?? "nil") name=\(app.localizedName ?? "nil") pid=\(app.processIdentifier) windows=\(windows.count) notificationWindows=\(notificationWindows.count)")
        }

        if notificationWindows.isEmpty {
            roots.append(axApp)
        } else {
            roots.append(contentsOf: notificationWindows)
        }
    }

    return roots
}

func isUsableVisibleNotificationCandidate(_ e: AXUIElement) -> Bool {
    if boolAttr(e, kAXHiddenAttribute) == true {
        return false
    }

    guard let frame = frameAttr(e) else {
        return false
    }

    return frame.size.width > 1 && frame.size.height > 1
}

func notificationCandidateIdentityKey(_ candidate: VisibleNotificationCandidate) -> String {
    let title = strAttr(candidate.element, kAXTitleAttribute) ?? ""
    let desc = strAttr(candidate.element, kAXDescriptionAttribute) ?? ""
    let id = strAttr(candidate.element, kAXIdentifierAttribute) ?? ""
    let actionKey = actions(candidate.element).joined(separator: "|")

    return [
        candidate.subrole,
        roundedFrameKey(candidate.frame),
        title,
        desc,
        id,
        actionKey
    ].joined(separator: "::")
}

func collectVisibleNotificationCandidates(
    _ e: AXUIElement,
    matchingSubroles targetSubroles: Set<String>,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
    visited: inout Set<CFHashCode>,
    candidates: inout [VisibleNotificationCandidate]
) {
    if depth > maxDepth { return }

    let hash = CFHash(e)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""

    if targetSubroles.contains(subrole), isUsableVisibleNotificationCandidate(e), let frame = frameAttr(e) {
        candidates.append(
            VisibleNotificationCandidate(
                element: e,
                subrole: subrole,
                frame: frame
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            collectVisibleNotificationCandidates(
                child,
                matchingSubroles: targetSubroles,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                candidates: &candidates
            )
        }
    }
}

func sortVisibleNotificationCandidates(_ candidates: [VisibleNotificationCandidate]) -> [VisibleNotificationCandidate] {
    candidates.sorted { a, b in
        let yDelta = abs(a.frame.minY - b.frame.minY)
        if yDelta > 1.0 {
            return a.frame.minY < b.frame.minY
        }

        let xDelta = abs(a.frame.minX - b.frame.minX)
        if xDelta > 1.0 {
            // Notification banners and stacks usually live at the right edge.
            // For equal vertical positions, prefer the rightmost candidate.
            return a.frame.minX > b.frame.minX
        }

        return roundedFrameKey(a.frame) < roundedFrameKey(b.frame)
    }
}

func visibleNotificationCandidates(matchingSubroles targetSubroles: Set<String>) -> [VisibleNotificationCandidate] {
    var allCandidates: [VisibleNotificationCandidate] = []

    for root in notificationSearchRoots() {
        var visited = Set<CFHashCode>()
        collectVisibleNotificationCandidates(
            root,
            matchingSubroles: targetSubroles,
            visited: &visited,
            candidates: &allCandidates
        )
    }

    var seenCandidateKeys = Set<String>()
    var deduplicated: [VisibleNotificationCandidate] = []

    for candidate in allCandidates {
        let key = notificationCandidateIdentityKey(candidate)
        guard !seenCandidateKeys.contains(key) else { continue }

        seenCandidateKeys.insert(key)
        deduplicated.append(candidate)
    }

    let sorted = sortVisibleNotificationCandidates(deduplicated)

    debugLog("VISIBLE NOTIFICATION CANDIDATES: raw=\(allCandidates.count) deduplicated=\(deduplicated.count)")
    for (index, candidate) in sorted.enumerated() {
        debugLog("  [\(index)] kind=\(candidate.kindLabel) frame=\(formatFrame(candidate.frame)) \(describe(candidate.element))")
    }

    return sorted
}

func topVisibleNotificationCandidate(
    subrole: String,
    actionNameContaining actionNameFragment: String
) -> VisibleNotificationCandidate? {
    visibleNotificationCandidates(matchingSubroles: [subrole]).first { candidate in
        actions(candidate.element).contains { actionName in
            actionName.localizedCaseInsensitiveContains(actionNameFragment)
        }
    }
}

func visibleNotificationSummaryLines() -> [String] {
    let candidates = visibleNotificationCandidates(
        matchingSubroles: [
            Config.notificationAlertSubrole,
            Config.notificationAlertStackSubrole
        ]
    )

    return candidates.enumerated().map { index, candidate in
        let actionList = actions(candidate.element).joined(separator: ", ")
        return "\(index + 1). \(candidate.kindLabel) frame=[\(formatFrame(candidate.frame))] actions=[\(actionList)] \(describe(candidate.element))"
    }
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
    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""
    let title = strAttr(e, kAXTitleAttribute) ?? ""
    let desc = strAttr(e, kAXDescriptionAttribute) ?? ""
    let id = strAttr(e, kAXIdentifierAttribute) ?? ""
    let acts = actions(e)

    let hasInterestingText =
        !title.isEmpty ||
        !desc.isEmpty ||
        !id.isEmpty ||
        !subrole.isEmpty ||
        !acts.isEmpty ||
        role.localizedCaseInsensitiveContains("menu") ||
        role.localizedCaseInsensitiveContains("button") ||
        subrole.localizedCaseInsensitiveContains("notification")

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

func dumpVisibleNotificationCandidates() {
    let lines = visibleNotificationSummaryLines()

    if lines.isEmpty {
        debugLog("DEBUG: no visible notification candidates found")
        return
    }

    for line in lines {
        debugLog("DEBUG: \(line)")
    }
}

// MARK: - Callable Engine

/// Public-facing notification engine.
///
/// clearNotifications() is the old reliable nuclear option. The newer targeted
/// actions are intentionally narrow and do not call the nuclear path.
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
            return .success("SUCCESS: cleared all notifications", didClear: true)
        }

        ensureNotificationCenterClosed()
        return .failure("PRESS FAILED")
    }

    /// Bare-bones targeted action.
    ///
    /// Finds the top visible single notification and performs its Name:Close action.
    /// This intentionally ignores stacks and does not expand them.
    static func closeTopVisibleNotification() -> Bool {
        let result = closeTopVisibleNotificationResult()
        return result.succeeded && result.didClear
    }

    /// Result-returning variant for the CLI.
    static func closeTopVisibleNotificationResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        guard let candidate = topVisibleNotificationCandidate(
            subrole: Config.notificationAlertSubrole,
            actionNameContaining: Config.notificationCloseActionNameFragment
        ) else {
            dumpLikelySystemWindows()
            return .success("Nothing to close: no visible single notification found", didClear: false)
        }

        debugLog("FOUND TOP VISIBLE SINGLE NOTIFICATION: \(describe(candidate.element))")

        if performFirstAction(on: candidate.element, nameContaining: Config.notificationCloseActionNameFragment) {
            return .success("SUCCESS: closed top visible notification", didClear: true)
        }

        return .failure("Close failed")
    }

    /// Bare-bones targeted action.
    ///
    /// Finds the top visible notification stack and performs its Name:Clear All action.
    /// This intentionally ignores single notifications and does not expand stacks.
    static func clearTopVisibleStack() -> Bool {
        let result = clearTopVisibleStackResult()
        return result.succeeded && result.didClear
    }

    /// Result-returning variant for the CLI.
    static func clearTopVisibleStackResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        guard let candidate = topVisibleNotificationCandidate(
            subrole: Config.notificationAlertStackSubrole,
            actionNameContaining: Config.notificationClearAllActionNameFragment
        ) else {
            dumpLikelySystemWindows()
            return .success("Nothing to clear: no visible notification stack found", didClear: false)
        }

        debugLog("FOUND TOP VISIBLE NOTIFICATION STACK: \(describe(candidate.element))")

        if performFirstAction(on: candidate.element, nameContaining: Config.notificationClearAllActionNameFragment) {
            return .success("SUCCESS: cleared top visible notification stack", didClear: true)
        }

        return .failure("Clear stack failed")
    }

    /// CLI/debug helper. Safe for the menu app to ignore.
    static func visibleNotificationSummaries() -> [String] {
        visibleNotificationSummaryLines()
    }
}

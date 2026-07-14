/*
 High-level execution flow:

 1. Keep the existing nuclear clear-all path:
    - Determine whether the actual Notification Center panel is already open.
    - Open Notification Center if necessary using the Clock menu extra.
    - Locate the Notification Center Accessibility window.
    - Locate the Clear (x) button.
    - Invoke "Clear All Notifications."
    - Ensure Notification Center is closed afterward.

 2. Add visible-notification actions that do not open Notification Center:
    - closeTopVisibleNotification(): find the top visible single alert and run Name:Close.
    - clearTopVisibleStack(): find the top visible stack and run Name:Clear All.
    - clearVisibleNotifications(): repeatedly clear visible singles/stacks until none remain.

 The nuclear path is intentionally separate from the newer targeted actions.
 The targeted actions do not expand stacks and do not open/close Notification Center.
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
    static let clearAllButtonDescription = "Clear All Notifications"

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

    static let clearVisibleMaxCycles = 50
    static let clearVisibleMaxActions = 200
    static let clearVisibleMaxConsecutiveNoProgressActions = 20
    static let clearVisibleProgressTimeout: TimeInterval = 0.35
    static let clearVisibleProgressPollingInterval: TimeInterval = 0.03
}

// MARK: - Debug Logging

enum Debug {
    static var isEnabled = false
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

// MARK: - Notification Center-Specific AX Search

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

/// Finds the direct bottom/global Clear All Notifications button in Notification Center.
///
/// In a filled Notification Center, macOS exposes the bottom X/clear-all control
/// as a plain AXButton with description "Clear All Notifications" and AXPress.
/// This is different from the top stack clear button, whose description is just
/// "Clear", and different from the older xmark -> AXShowMenu fallback path.
func findDirectClearAllNotificationsButton(
    _ e: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth
) -> AXUIElement? {
    findElement(e, depth: depth, maxDepth: maxDepth) { node in
        let role = strAttr(node, kAXRoleAttribute) ?? ""
        let textValues = [
            strAttr(node, kAXTitleAttribute),
            strAttr(node, kAXDescriptionAttribute),
            strAttr(node, kAXHelpAttribute)
        ].compactMap { $0 }

        let hasClearAllText = textValues.contains { value in
            value == Config.clearAllButtonDescription
        }

        let isButtonLike =
            role == kAXButtonRole as String ||
            role == kAXMenuButtonRole as String

        let isPressable = actions(node).contains(kAXPressAction as String)

        return isButtonLike && hasClearAllText && isPressable
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

enum VisibleNotificationKind: String, Hashable {
    case single
    case stack

    init?(subrole: String) {
        switch subrole {
        case Config.notificationAlertSubrole:
            self = .single
        case Config.notificationAlertStackSubrole:
            self = .stack
        default:
            return nil
        }
    }

    var subrole: String {
        switch self {
        case .single:
            return Config.notificationAlertSubrole
        case .stack:
            return Config.notificationAlertStackSubrole
        }
    }

    var actionNameFragment: String {
        switch self {
        case .single:
            return Config.notificationCloseActionNameFragment
        case .stack:
            return Config.notificationClearAllActionNameFragment
        }
    }

    var label: String {
        switch self {
        case .single:
            return "single"
        case .stack:
            return "stack"
        }
    }
}

struct VisibleNotificationItem {
    let element: AXUIElement
    let kind: VisibleNotificationKind
    let frame: CGRect

    var kindLabel: String {
        kind.label
    }

    var isActionable: Bool {
        actions(element).contains { actionName in
            actionName.localizedCaseInsensitiveContains(kind.actionNameFragment)
        }
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

func isUsableVisibleNotificationItem(_ e: AXUIElement) -> Bool {
    if boolAttr(e, kAXHiddenAttribute) == true {
        return false
    }

    guard let frame = frameAttr(e) else {
        return false
    }

    return frame.size.width > 1 && frame.size.height > 1
}

func visibleNotificationItemIdentityKey(_ item: VisibleNotificationItem) -> String {
    let title = strAttr(item.element, kAXTitleAttribute) ?? ""
    let desc = strAttr(item.element, kAXDescriptionAttribute) ?? ""
    let id = strAttr(item.element, kAXIdentifierAttribute) ?? ""
    let actionKey = actions(item.element).joined(separator: "|")

    return [
        item.kind.rawValue,
        roundedFrameKey(item.frame),
        title,
        desc,
        id,
        actionKey
    ].joined(separator: "::")
}

func collectVisibleNotificationItems(
    _ e: AXUIElement,
    matchingKinds targetKinds: Set<VisibleNotificationKind>? = nil,
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
    visited: inout Set<CFHashCode>,
    items: inout [VisibleNotificationItem]
) {
    if depth > maxDepth { return }

    let hash = CFHash(e)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let subrole = strAttr(e, kAXSubroleAttribute) ?? ""

    if
        let kind = VisibleNotificationKind(subrole: subrole),
        targetKinds == nil || targetKinds!.contains(kind),
        isUsableVisibleNotificationItem(e),
        let frame = frameAttr(e)
    {
        items.append(
            VisibleNotificationItem(
                element: e,
                kind: kind,
                frame: frame
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(e, name) {
            collectVisibleNotificationItems(
                child,
                matchingKinds: targetKinds,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                items: &items
            )
        }
    }
}

func sortVisibleNotificationItems(_ items: [VisibleNotificationItem]) -> [VisibleNotificationItem] {
    items.sorted { a, b in
        let yDelta = abs(a.frame.minY - b.frame.minY)
        if yDelta > 1.0 {
            return a.frame.minY < b.frame.minY
        }

        let xDelta = abs(a.frame.minX - b.frame.minX)
        if xDelta > 1.0 {
            // Notification banners and stacks usually live at the right edge.
            // For equal vertical positions, prefer the rightmost item.
            return a.frame.minX > b.frame.minX
        }

        return roundedFrameKey(a.frame) < roundedFrameKey(b.frame)
    }
}

func visibleNotificationItems(
    matchingKinds targetKinds: Set<VisibleNotificationKind>? = nil,
    debugDump: Bool = false
) -> [VisibleNotificationItem] {
    var allItems: [VisibleNotificationItem] = []

    for root in notificationSearchRoots(logFound: debugDump) {
        var visited = Set<CFHashCode>()
        collectVisibleNotificationItems(
            root,
            matchingKinds: targetKinds,
            visited: &visited,
            items: &allItems
        )
    }

    var seenItemKeys = Set<String>()
    var deduplicated: [VisibleNotificationItem] = []

    for item in allItems {
        let key = visibleNotificationItemIdentityKey(item)
        guard !seenItemKeys.contains(key) else { continue }

        seenItemKeys.insert(key)
        deduplicated.append(item)
    }

    let sorted = sortVisibleNotificationItems(deduplicated)

    if debugDump {
        debugLog("VISIBLE_SCAN: raw=\(allItems.count) deduplicated=\(deduplicated.count)")
        for (index, item) in sorted.enumerated() {
            debugLog("  [\(index)] kind=\(item.kindLabel) frame=\(formatFrame(item.frame)) actionable=\(item.isActionable) \(compactDescribe(item.element))")
        }
    }

    return sorted
}

func topVisibleNotificationItem(
    kind: VisibleNotificationKind
) -> VisibleNotificationItem? {
    visibleNotificationItems(matchingKinds: [kind]).first { item in
        item.isActionable
    }
}

func clearVisibleNotificationItem(_ item: VisibleNotificationItem) -> Bool {
    performFirstAction(on: item.element, nameContaining: item.kind.actionNameFragment)
}


func visibleNotificationStableKey(_ item: VisibleNotificationItem) -> String {
    let id = strAttr(item.element, kAXIdentifierAttribute) ?? ""
    if !id.isEmpty {
        return "\(item.kind.rawValue)::id::\(id)"
    }

    let title = strAttr(item.element, kAXTitleAttribute) ?? ""
    let desc = strAttr(item.element, kAXDescriptionAttribute) ?? ""
    let actionKey = actions(item.element).joined(separator: "|")

    // Fallback for OS versions/elements that do not expose AXIdentifier.
    // Avoid frame here because notification frames move during animations.
    return [
        item.kind.rawValue,
        title,
        desc,
        actionKey
    ].joined(separator: "::")
}

func countVisibleNotificationItems(_ items: [VisibleNotificationItem], kind: VisibleNotificationKind) -> Int {
    items.filter { $0.kind == kind }.count
}

func topActionableVisibleNotificationItem(
    kind: VisibleNotificationKind,
    in items: [VisibleNotificationItem]
) -> VisibleNotificationItem? {
    items.first { item in
        item.kind == kind && item.isActionable
    }
}

/// Waits until an AX action appears to have made real visible progress.
///
/// Important: AXUIElementPerformAction can return success even while the
/// notification remains visible during redraw/animation. This helper does not
/// assume that a successful AX action means a notification was actually removed.
func waitForVisibleNotificationProgress(
    afterClearing targetItem: VisibleNotificationItem,
    previousItems: [VisibleNotificationItem]
) -> Bool {
    let targetKey = visibleNotificationStableKey(targetItem)
    let previousAllCount = previousItems.count
    let previousKindCount = countVisibleNotificationItems(previousItems, kind: targetItem.kind)
    let deadline = Date().addingTimeInterval(Config.clearVisibleProgressTimeout)

    while Date() < deadline {
        let currentItems = visibleNotificationItems()
        let currentAllCount = currentItems.count
        let currentKindCount = countVisibleNotificationItems(currentItems, kind: targetItem.kind)
        let targetStillVisible = currentItems.contains { item in
            visibleNotificationStableKey(item) == targetKey
        }

        if !targetStillVisible || currentAllCount < previousAllCount || currentKindCount < previousKindCount {
            debugLog("CLEAR_VISIBLE: progress targetStillVisible=\(targetStillVisible) all=\(previousAllCount)->\(currentAllCount) kind=\(previousKindCount)->\(currentKindCount)")
            return true
        }

        Thread.sleep(forTimeInterval: Config.clearVisibleProgressPollingInterval)
    }

    debugLog("CLEAR_VISIBLE: no observed progress kind=\(targetItem.kindLabel) targetKey=\(shortenedAXText(targetKey, maxLength: 120))")
    return false
}

func visibleNotificationSummaryLines() -> [String] {
    visibleNotificationItems().enumerated().map { index, item in
        let actionList = actions(item.element).joined(separator: ", ")
        return "\(index + 1). \(item.kindLabel) actionable=\(item.isActionable) frame=[\(formatFrame(item.frame))] actions=[\(actionList)] \(describe(item.element))"
    }
}

// MARK: - Notification Clearing

/// Waits briefly for the direct Clear All Notifications button to appear.
///
/// This is the preferred path for the nuclear clear-all operation. In filled
/// Notification Center layouts, this button may be lower than the visible window
/// frame, but still present in the Accessibility tree.
func waitForDirectClearAllNotificationsButton(in window: AXUIElement) -> AXUIElement? {
    var button: AXUIElement?

    let found = waitUntil(timeout: Config.defaultPollingTimeout, interval: Config.defaultPollingInterval) {
        button = findDirectClearAllNotificationsButton(window)
        return button != nil
    }

    return found ? button : nil
}

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

struct AXDumpCandidate {
    let appName: String
    let bundleID: String
    let pid: pid_t
    let element: AXUIElement
    let frame: CGRect?
    let role: String?
    let subrole: String?
    let identifier: String?
    let title: String?
    let desc: String?
    let help: String?
    let actions: [String]
    let reasons: [String]
    let path: [String]
}

struct AXDumpMenuItem {
    let role: String?
    let title: String?
    let desc: String?
    let frame: CGRect?
    let actions: [String]
}

func formatFrameWithMaxY(_ rect: CGRect?) -> String {
    guard let rect else { return "nil" }

    return String(
        format: "x=%.0f y=%.0f w=%.0f h=%.0f maxY=%.0f",
        rect.origin.x,
        rect.origin.y,
        rect.size.width,
        rect.size.height,
        rect.maxY
    )
}

func axDumpElementPathPart(_ element: AXUIElement) -> String {
    let role = strAttr(element, kAXRoleAttribute) ?? "?"
    let subrole = strAttr(element, kAXSubroleAttribute)
    let identifier = strAttr(element, kAXIdentifierAttribute)
    let title = strAttr(element, kAXTitleAttribute)
    let desc = strAttr(element, kAXDescriptionAttribute)

    var pieces = [role]

    if let subrole, !subrole.isEmpty {
        pieces.append("subrole=\(subrole)")
    }

    if let identifier, !identifier.isEmpty {
        pieces.append("id=\(shortenedAXText(identifier, maxLength: 36))")
    }

    if let title, !title.isEmpty {
        pieces.append("title=\(shortenedAXText(title, maxLength: 36))")
    } else if let desc, !desc.isEmpty {
        pieces.append("desc=\(shortenedAXText(desc, maxLength: 36))")
    }

    return pieces.joined(separator: " ")
}

func axDumpReasons(
    role: String?,
    subrole: String?,
    identifier: String?,
    title: String?,
    desc: String?,
    help: String?,
    actions: [String]
) -> [String] {
    var reasons: [String] = []

    let text = [role, subrole, identifier, title, desc, help]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    let actionText = actions.joined(separator: " ").lowercased()
    let roleText = role ?? ""

    if identifier?.localizedCaseInsensitiveContains(Config.clearButtonIdentifier) == true {
        reasons.append("identifier contains xmark")
    }

    if text.contains("clear") {
        reasons.append("text contains clear")
    }

    if text.contains("close") {
        reasons.append("text contains close")
    }

    if text.contains("notification") {
        reasons.append("text contains notification")
    }

    if actions.contains(kAXShowMenuAction as String) {
        reasons.append("has AXShowMenu")
    }

    if actionText.contains("clear") {
        reasons.append("action contains clear")
    }

    if actionText.contains("close") {
        reasons.append("action contains close")
    }

    if subrole == Config.notificationAlertSubrole || subrole == Config.notificationAlertStackSubrole {
        reasons.append("notification item")
    }

    if (
        roleText == kAXButtonRole as String ||
        roleText == kAXMenuButtonRole as String
    ), !reasons.isEmpty {
        reasons.append("button-like")
    }

    return reasons
}

func collectAXDumpCandidates(
    _ element: AXUIElement,
    appName: String,
    bundleID: String,
    pid: pid_t,
    path: [String],
    depth: Int = 0,
    maxDepth: Int = Config.defaultAXTreeSearchMaxDepth,
    visited: inout Set<CFHashCode>,
    candidates: inout [AXDumpCandidate]
) {
    if depth > maxDepth { return }

    let hash = CFHash(element)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let role = strAttr(element, kAXRoleAttribute)
    let subrole = strAttr(element, kAXSubroleAttribute)
    let identifier = strAttr(element, kAXIdentifierAttribute)
    let title = strAttr(element, kAXTitleAttribute)
    let desc = strAttr(element, kAXDescriptionAttribute)
    let help = strAttr(element, kAXHelpAttribute)
    let elementActions = actions(element)
    let reasons = axDumpReasons(
        role: role,
        subrole: subrole,
        identifier: identifier,
        title: title,
        desc: desc,
        help: help,
        actions: elementActions
    )

    let currentPath = path + [axDumpElementPathPart(element)]

    if !reasons.isEmpty {
        candidates.append(
            AXDumpCandidate(
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                element: element,
                frame: frameAttr(element),
                role: role,
                subrole: subrole,
                identifier: identifier,
                title: title,
                desc: desc,
                help: help,
                actions: elementActions,
                reasons: reasons,
                path: currentPath
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(element, name) {
            collectAXDumpCandidates(
                child,
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                path: currentPath,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                candidates: &candidates
            )
        }
    }
}

func collectAXDumpMenuItems(
    _ element: AXUIElement,
    depth: Int = 0,
    maxDepth: Int = 12,
    visited: inout Set<CFHashCode>,
    items: inout [AXDumpMenuItem]
) {
    if depth > maxDepth { return }

    let hash = CFHash(element)
    if visited.contains(hash) { return }
    visited.insert(hash)

    let role = strAttr(element, kAXRoleAttribute)
    let title = strAttr(element, kAXTitleAttribute)
    let desc = strAttr(element, kAXDescriptionAttribute)
    let elementFrame = frameAttr(element)
    let elementActions = actions(element)

    let roleText = role?.lowercased() ?? ""
    let text = [title, desc]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

    let hasRelevantText =
        text.contains("clear") ||
        text.contains("notification") ||
        text.contains("mute") ||
        text.contains("turn off") ||
        text.contains("settings")

    let isRealMenu =
        (roleText.contains("menu") || roleText.contains("button")) &&
        ((elementFrame?.width ?? 0) > 1) &&
        ((elementFrame?.height ?? 0) > 1)

    if hasRelevantText || isRealMenu {
        items.append(
            AXDumpMenuItem(
                role: role,
                title: title,
                desc: desc,
                frame: elementFrame,
                actions: elementActions
            )
        )
    }

    for name in [kAXVisibleChildrenAttribute, kAXChildrenAttribute, "AXChildrenInNavigationOrder"] {
        for child in children(element, name) {
            collectAXDumpMenuItems(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                visited: &visited,
                items: &items
            )
        }
    }
}

func pressEscapeForAXDump() {
    let source = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)

    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

func dumpNotificationCenterAXControlsImpl(probeMenus: Bool) {
    print("AX trusted: \(AXIsProcessTrusted())")

    var allCandidates: [AXDumpCandidate] = []

    for app in notificationCenterApplications() {
        let bundleID = app.bundleIdentifier ?? "unknown"
        let appName = app.localizedName ?? "unknown"
        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        let windows = children(axApp, kAXWindowsAttribute)
        let notificationWindows = windows.filter(isNotificationCenterWindow)
        let roots = notificationWindows.isEmpty ? [axApp] : notificationWindows

        print("APP: \(appName) bundle=\(bundleID) pid=\(pid) windows=\(windows.count) notificationWindows=\(notificationWindows.count)")

        if notificationWindows.isEmpty {
            var visited = Set<CFHashCode>()
            collectAXDumpCandidates(
                axApp,
                appName: appName,
                bundleID: bundleID,
                pid: pid,
                path: ["\(appName) pid=\(pid)", "app"],
                visited: &visited,
                candidates: &allCandidates
            )
        } else {
            for window in roots {
                let title = strAttr(window, kAXTitleAttribute)
                print("  WINDOW: title=\(shortenedAXText(title, maxLength: 80)) frame=\(formatFrameWithMaxY(frameAttr(window)))")

                var visited = Set<CFHashCode>()
                collectAXDumpCandidates(
                    window,
                    appName: appName,
                    bundleID: bundleID,
                    pid: pid,
                    path: ["\(appName) pid=\(pid)", "window=\(shortenedAXText(title, maxLength: 80))"],
                    visited: &visited,
                    candidates: &allCandidates
                )
            }
        }
    }

    let candidates = allCandidates.sorted { left, right in
        let leftMaxY = left.frame?.maxY ?? -Double.greatestFiniteMagnitude
        let rightMaxY = right.frame?.maxY ?? -Double.greatestFiniteMagnitude

        if leftMaxY != rightMaxY {
            return leftMaxY > rightMaxY
        }

        return (left.frame?.minX ?? 0) > (right.frame?.minX ?? 0)
    }

    print("")
    print("FOUND \(candidates.count) suspicious Notification Center AX candidate(s), sorted bottom-to-top")
    print("")

    for (index, candidate) in candidates.enumerated() {
        print("[\(index)]")
        print("  app: \(candidate.appName) bundle=\(candidate.bundleID) pid=\(candidate.pid)")
        print("  frame: \(formatFrameWithMaxY(candidate.frame))")
        print("  role: \(shortenedAXText(candidate.role, maxLength: 80))")
        print("  subrole: \(shortenedAXText(candidate.subrole, maxLength: 80))")
        print("  identifier: \(shortenedAXText(candidate.identifier, maxLength: 80))")
        print("  title: \(shortenedAXText(candidate.title, maxLength: 100))")
        print("  desc: \(shortenedAXText(candidate.desc, maxLength: 100))")
        print("  help: \(shortenedAXText(candidate.help, maxLength: 100))")
        print("  actions: \(candidate.actions.joined(separator: ", "))")
        print("  reasons: \(candidate.reasons.joined(separator: ", "))")
        print("  path:")

        for pathPart in candidate.path {
            print("    \(pathPart)")
        }

        if probeMenus, candidate.actions.contains(kAXShowMenuAction as String) {
            print("  menu probe:")

            let result = AXUIElementPerformAction(candidate.element, kAXShowMenuAction as CFString)
            print("    AXShowMenu result: \(result.rawValue) \(result)")
            Thread.sleep(forTimeInterval: 0.25)

            let axApp = AXUIElementCreateApplication(candidate.pid)
            var visited = Set<CFHashCode>()
            var menuItems: [AXDumpMenuItem] = []
            collectAXDumpMenuItems(
                axApp,
                visited: &visited,
                items: &menuItems
            )

            if menuItems.isEmpty {
                print("    no relevant menu-ish items found after AXShowMenu")
            } else {
                for (menuIndex, item) in menuItems.prefix(60).enumerated() {
                    print("    [menu \(menuIndex)] role=\(shortenedAXText(item.role, maxLength: 60)) title=\(shortenedAXText(item.title, maxLength: 100)) desc=\(shortenedAXText(item.desc, maxLength: 100)) frame=\(formatFrameWithMaxY(item.frame)) actions=\(item.actions.joined(separator: ", "))")
                }

                if menuItems.count > 60 {
                    print("    ... \(menuItems.count - 60) additional relevant menu-ish item(s) omitted")
                }
            }

            pressEscapeForAXDump()
            Thread.sleep(forTimeInterval: 0.10)
        }

        print("")
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

        debugLog("CLEAR_ALL: window \(compactDescribe(window))")

        // Preferred path: the bottom/global clear-all control is sometimes
        // exposed directly as an AXButton with description "Clear All Notifications".
        // This handles the filled Notification Center case where the old xmark/menu
        // search could find the top per-stack clear control instead.
        if let directClearAllButton = waitForDirectClearAllNotificationsButton(in: window) {
            debugLog("CLEAR_ALL: found direct Clear All Notifications button \(compactDescribe(directClearAllButton))")

            if press(directClearAllButton) {
                ensureNotificationCenterClosed()
                return .success("SUCCESS: cleared all notifications", didClear: true)
            }

            debugLog("CLEAR_ALL: direct button press failed; trying xmark/menu fallback")
        } else {
            debugLog("CLEAR_ALL: direct button not found; trying xmark/menu fallback")
        }

        // Fallback path: older/normal layouts expose Clear All Notifications only
        // after showing the xmark/menu-button menu.
        guard let xmark = findXmark(window) else {
            ensureNotificationCenterClosed()
            return .success("Nothing to clear: Clear All Notifications control not found", didClear: false)
        }

        debugLog("CLEAR_ALL: found xmark fallback \(compactDescribe(xmark))")

        let showErr = AXUIElementPerformAction(xmark, kAXShowMenuAction as CFString)
        debugLog("CLEAR_ALL: AXShowMenu result \(showErr.rawValue) \(showErr)")

        guard let clearItem = waitForClearAll(in: window) else {
            ensureNotificationCenterClosed()
            return .success("Nothing to clear: Clear All Notifications menu item not found", didClear: false)
        }

        debugLog("CLEAR_ALL: found Clear All menu item fallback \(compactDescribe(clearItem))")

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

        guard let item = topVisibleNotificationItem(kind: .single) else {
            dumpLikelySystemWindows()
            return .success("Nothing to clear: no visible single notification found", didClear: false)
        }

        debugLog("CLEAR_SINGLE: found top visible single notification \(compactDescribe(item.element))")

        if clearVisibleNotificationItem(item) {
            return .success("SUCCESS: cleared top visible single notification", didClear: true)
        }

        return .failure("Clear single notification failed")
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

        guard let item = topVisibleNotificationItem(kind: .stack) else {
            dumpLikelySystemWindows()
            return .success("Nothing to clear: no visible notification stack found", didClear: false)
        }

        debugLog("CLEAR_STACK: found top visible notification stack \(compactDescribe(item.element))")

        if clearVisibleNotificationItem(item) {
            return .success("SUCCESS: cleared top visible notification stack", didClear: true)
        }

        return .failure("Clear stack failed")
    }

    /// Clears visible notifications without opening Notification Center.
    ///
    /// This repeatedly takes a fresh snapshot of visible single notifications and
    /// visible stacks, clears the top actionable item, waits briefly for macOS to
    /// update the AX tree, then repeats until nothing actionable is visible.
    static func clearVisibleNotifications() -> ClearNotificationsResult {
        let result = clearVisibleNotificationsResult()
        return result
    }

    /// Result-returning variant for the CLI.
    static func clearVisibleNotificationsResult() -> ClearNotificationsResult {
        debugLog("AX trusted: \(AXIsProcessTrusted())")

        var didClearAnything = false
        var actionCount = 0
        var observedProgressCount = 0
        var consecutiveNoProgressActions = 0

        for cycle in 1...Config.clearVisibleMaxCycles {
            let cycleStartItems = visibleNotificationItems()
            let cycleStartActionableItems = cycleStartItems.filter { $0.isActionable }

            if cycleStartActionableItems.isEmpty {
                if didClearAnything {
                    return .success(
                        "SUCCESS: cleared visible notifications with \(actionCount) AX action(s) and \(observedProgressCount) observed progress event(s)",
                        didClear: true
                    )
                } else {
                    return .success("Nothing to clear: no visible notifications found", didClear: false)
                }
            }

            let singleCount = countVisibleNotificationItems(cycleStartActionableItems, kind: .single)
            let stackCount = countVisibleNotificationItems(cycleStartActionableItems, kind: .stack)
            debugLog("CLEAR_VISIBLE: cycle=\(cycle) singles=\(singleCount) stacks=\(stackCount) total=\(cycleStartActionableItems.count)")

            // Order does not matter for the visible sweep. Clear singles first,
            // then stacks. Each action uses a fresh snapshot and waits for
            // observed progress before moving on.
            for kind in [VisibleNotificationKind.single, VisibleNotificationKind.stack] {
                while true {
                    let beforeItems = visibleNotificationItems()

                    guard let item = topActionableVisibleNotificationItem(kind: kind, in: beforeItems) else {
                        break
                    }

                    if actionCount >= Config.clearVisibleMaxActions {
                        return .failure(
                            "Stopped after \(actionCount) visible clear AX action(s); visible notifications may remain"
                        )
                    }

                    debugLog("CLEAR_VISIBLE: action=\(actionCount + 1) kind=\(item.kindLabel) frame=\(formatFrame(item.frame))")

                    guard clearVisibleNotificationItem(item) else {
                        return .failure("Clear visible failed on \(item.kindLabel) after \(actionCount) AX action(s)")
                    }

                    didClearAnything = true
                    actionCount += 1

                    let observedProgress = waitForVisibleNotificationProgress(
                        afterClearing: item,
                        previousItems: beforeItems
                    )

                    if observedProgress {
                        observedProgressCount += 1
                        consecutiveNoProgressActions = 0
                    } else {
                        consecutiveNoProgressActions += 1

                        if consecutiveNoProgressActions >= Config.clearVisibleMaxConsecutiveNoProgressActions {
                            return .failure(
                                "Stopped after \(actionCount) visible clear AX action(s); no visible progress was observed for \(consecutiveNoProgressActions) consecutive action(s)"
                            )
                        }
                    }
                }
            }
        }

        return .failure(
            "Stopped after \(Config.clearVisibleMaxCycles) visible clear cycle(s); visible notifications may remain"
        )
    }

    /// Diagnostic helper for AX reverse-engineering. This intentionally prints
    /// a large amount of information and may perturb Notification Center state
    /// when menu probing is enabled.
    static func dumpNotificationCenterAXControls(probeMenus: Bool = false) {
        dumpNotificationCenterAXControlsImpl(probeMenus: probeMenus)
    }

    /// CLI/debug helper. Safe for the menu app to ignore.
    static func visibleNotificationSummaries() -> [String] {
        visibleNotificationSummaryLines()
    }
}

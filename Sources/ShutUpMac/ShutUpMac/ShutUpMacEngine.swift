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

// MARK: - Notification Clear-All AX Search

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

    /// Diagnostic helper for AX reverse-engineering. This intentionally prints
    /// a large amount of information and may perturb Notification Center state
    /// when menu probing is enabled.
    static func dumpNotificationCenterAXControls(probeMenus: Bool = false) {
        dumpNotificationCenterAXControlsImpl(probeMenus: probeMenus)
    }
}

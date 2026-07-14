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

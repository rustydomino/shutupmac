import Foundation
import ApplicationServices
import CoreGraphics
import AppKit

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

// MARK: - Notification Clearing API

extension ShutUpMac {
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

}

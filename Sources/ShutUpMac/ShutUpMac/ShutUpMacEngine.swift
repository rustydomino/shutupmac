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
    - clearVisibleNotifications(): repeatedly clear desktop-visible singles/stacks until none remain.

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

// MARK: - Callable Engine

/// Public-facing notification engine.
///
/// Behavior-specific implementations live in focused files:
/// - NotificationClearAll.swift
/// - VisibleNotifications.swift
/// - AXDiagnostics.swift
enum ShutUpMac {
    /// Diagnostic helper for AX reverse-engineering. This intentionally prints
    /// a large amount of information and may perturb Notification Center state
    /// when menu probing is enabled.
    static func dumpNotificationCenterAXControls(probeMenus: Bool = false) {
        dumpNotificationCenterAXControlsImpl(probeMenus: probeMenus)
    }
}

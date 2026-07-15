import Foundation
import ApplicationServices

enum NotificationClearer {
    static func clearMostRecent() {
        performClearAction {
            ShutUpMac.clearMostRecentVisibleNotificationResult()
        }
    }

    static func clearVisible() {
        performClearAction {
            ShutUpMac.clearVisibleNotificationsResult()
        }
    }

    static func clearAll() {
        performClearAction {
            ShutUpMac.clearNotifications()
        }
    }

    // Keep this for old call sites, especially any legacy hotkey/menu handlers.
    // For now, the existing "clear" behavior remains "clear all".
    static func clear() {
        clearAll()
    }

    private static func performClearAction(_ action: () -> ClearNotificationsResult) {
        guard AccessibilityPermission.isTrusted(prompt: true) else {
            print("AX trusted: false")
            print("ShutUpMac needs Accessibility permission before it can clear notifications.")
            return
        }

        print("AX trusted: true")

        let result = action()

        print(result.message)
    }
}

enum AccessibilityPermission {
    static func isTrusted(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
}

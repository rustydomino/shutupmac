import Foundation
import ApplicationServices

enum NotificationClearer {
    static func clear() {
        guard AccessibilityPermission.isTrusted(prompt: true) else {
            print("AX trusted: false")
            print("ShutUpMac needs Accessibility permission before it can clear notifications.")
            return
        }

        print("AX trusted: true")

        let result = ShutUpMac.clearNotifications()

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

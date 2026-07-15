import Foundation
import AppKit

enum PreferenceKeys {
    static let hideDockIcon = "hideDockIcon"
    static let enableGlobalHotkeys = "enableGlobalHotkeys"

    static let clearVisibleNotificationsHotKey = "clearVisibleNotificationsHotKey"
    static let clearAllNotificationsHotKey = "clearAllNotificationsHotKey"
    static let testNotificationHotKey = "testNotificationHotKey"

    // Legacy key from the old single-clear-hotkey design.
    static let clearNotificationsHotKey = "clearNotificationsHotKey"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.hideDockIcon: true,
            PreferenceKeys.enableGlobalHotkeys: true,
            PreferenceKeys.clearVisibleNotificationsHotKey: HotKey.defaultClearDesktop.encodedString,
            PreferenceKeys.clearAllNotificationsHotKey: HotKey.defaultClearAll.encodedString,
            PreferenceKeys.testNotificationHotKey: HotKey.defaultTestNotification.encodedString,

            // Keep a default for older code/preferences. New code should not use this.
            PreferenceKeys.clearNotificationsHotKey: HotKey.defaultClear.encodedString
        ])

        migrateClearDesktopHotKeyDefaultIfNeeded()
    }

    static var hideDockIcon: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.hideDockIcon)
    }

    static var enableGlobalHotkeys: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.enableGlobalHotkeys)
    }

    static var clearVisibleNotificationsHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(
            forKey: PreferenceKeys.clearVisibleNotificationsHotKey
        )

        return HotKey.decode(storedValue) ?? .defaultClearDesktop
    }

    static var clearAllNotificationsHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(
            forKey: PreferenceKeys.clearAllNotificationsHotKey
        )

        return HotKey.decode(storedValue) ?? .defaultClearAll
    }

    static var testNotificationHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(
            forKey: PreferenceKeys.testNotificationHotKey
        )

        return HotKey.decode(storedValue) ?? .defaultTestNotification
    }

    // Legacy accessor from the old single-clear-hotkey design.
    static var clearNotificationsHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(
            forKey: PreferenceKeys.clearNotificationsHotKey
        )

        return HotKey.decode(storedValue) ?? .defaultClear
    }

    private static func migrateClearDesktopHotKeyDefaultIfNeeded() {
        let currentValue = UserDefaults.standard.string(
            forKey: PreferenceKeys.clearVisibleNotificationsHotKey
        )

        guard currentValue == HotKey.legacyDefaultClearVisible.encodedString else {
            return
        }

        UserDefaults.standard.set(
            HotKey.defaultClearDesktop.encodedString,
            forKey: PreferenceKeys.clearVisibleNotificationsHotKey
        )
    }
}

enum DockIconController {
    static func apply(hideDockIcon: Bool) {
        if hideDockIcon {
            NSApplication.shared.setActivationPolicy(.accessory)
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }
}

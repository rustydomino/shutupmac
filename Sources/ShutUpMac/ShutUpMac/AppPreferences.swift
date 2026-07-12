import Foundation
import AppKit

enum PreferenceKeys {
    static let hideDockIcon = "hideDockIcon"
    static let enableGlobalHotkeys = "enableGlobalHotkeys"
    static let clearNotificationsHotKey = "clearNotificationsHotKey"
    static let testNotificationHotKey = "testNotificationHotKey"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.hideDockIcon: true,
            PreferenceKeys.enableGlobalHotkeys: true,
            PreferenceKeys.clearNotificationsHotKey: HotKey.defaultClear.encodedString,
            PreferenceKeys.testNotificationHotKey: HotKey.defaultTestNotification.encodedString
        ])
    }

    static var hideDockIcon: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.hideDockIcon)
    }

    static var enableGlobalHotkeys: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.enableGlobalHotkeys)
    }

    static var clearNotificationsHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(forKey: PreferenceKeys.clearNotificationsHotKey)
        return HotKey.decode(storedValue) ?? .defaultClear
    }

    static var testNotificationHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(forKey: PreferenceKeys.testNotificationHotKey)
        return HotKey.decode(storedValue) ?? .defaultTestNotification
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

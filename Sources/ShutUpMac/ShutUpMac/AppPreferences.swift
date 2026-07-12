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
            PreferenceKeys.clearNotificationsHotKey: HotKeyChoice.controlOptionCommandD.rawValue,
            PreferenceKeys.testNotificationHotKey: HotKeyChoice.controlOptionCommandS.rawValue
        ])
    }

    static var hideDockIcon: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.hideDockIcon)
    }

    static var enableGlobalHotkeys: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.enableGlobalHotkeys)
    }

    static var clearNotificationsHotKey: HotKeyChoice {
        let rawValue = UserDefaults.standard.string(forKey: PreferenceKeys.clearNotificationsHotKey)
        return HotKeyChoice(rawValue: rawValue ?? "") ?? .controlOptionCommandD
    }

    static var testNotificationHotKey: HotKeyChoice {
        let rawValue = UserDefaults.standard.string(forKey: PreferenceKeys.testNotificationHotKey)
        return HotKeyChoice(rawValue: rawValue ?? "") ?? .controlOptionCommandS
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

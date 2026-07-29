import Foundation
import AppKit
import NotilogCore

enum PreferenceKeys {
    static let enableGlobalHotkeys = "enableGlobalHotkeys"

    static let notilogDatabaseLoggingEnabled =
        "notilogDatabaseLoggingEnabled"

    static let notilogRedactionEnabled =
        "notilogRedactionEnabled"

    static let notilogRedactTitle =
        "notilogRedactTitle"

    static let notilogRedactSubtitle =
        "notilogRedactSubtitle"

    static let notilogRedactBody =
        "notilogRedactBody"

    static let clearMostRecentNotificationHotKey = "clearMostRecentNotificationHotKey"
    static let clearVisibleNotificationsHotKey = "clearVisibleNotificationsHotKey"
    static let clearAllNotificationsHotKey = "clearAllNotificationsHotKey"
    static let testNotificationHotKey = "testNotificationHotKey"

    // Legacy key from the old single-clear-hotkey design.
    static let clearNotificationsHotKey = "clearNotificationsHotKey"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.enableGlobalHotkeys: true,
            PreferenceKeys.notilogDatabaseLoggingEnabled: true,
            PreferenceKeys.notilogRedactionEnabled: false,
            PreferenceKeys.notilogRedactTitle: true,
            PreferenceKeys.notilogRedactSubtitle: true,
            PreferenceKeys.notilogRedactBody: true,
            PreferenceKeys.clearMostRecentNotificationHotKey:
                HotKey.defaultClearMostRecent.encodedString,
            PreferenceKeys.clearVisibleNotificationsHotKey:
                HotKey.defaultClearDesktop.encodedString,
            PreferenceKeys.clearAllNotificationsHotKey:
                HotKey.defaultClearAll.encodedString,
            PreferenceKeys.testNotificationHotKey:
                HotKey.defaultTestNotification.encodedString,

            // Keep a default for older code/preferences.
            PreferenceKeys.clearNotificationsHotKey:
                HotKey.defaultClear.encodedString
        ])

        migrateClearDesktopHotKeyDefaultIfNeeded()
    }

    static var enableGlobalHotkeys: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.enableGlobalHotkeys)
    }

    static var clearMostRecentNotificationHotKey: HotKey {
        let storedValue = UserDefaults.standard.string(
            forKey: PreferenceKeys.clearMostRecentNotificationHotKey
        )

        return HotKey.decode(storedValue) ?? .defaultClearMostRecent
    }

    static var notilogDatabaseLoggingEnabled: Bool {
        UserDefaults.standard.bool(
            forKey:
                PreferenceKeys
                    .notilogDatabaseLoggingEnabled
        )
    }

    static func setNotilogDatabaseLoggingEnabled(
        _ enabled: Bool
    ) {
        UserDefaults.standard.set(
            enabled,
            forKey:
                PreferenceKeys
                    .notilogDatabaseLoggingEnabled
        )
    }

    static var notilogRedactionEnabled: Bool {
        UserDefaults.standard.bool(
            forKey: PreferenceKeys.notilogRedactionEnabled
        )
    }

    static var notilogRedactTitle: Bool {
        UserDefaults.standard.bool(
            forKey: PreferenceKeys.notilogRedactTitle
        )
    }

    static var notilogRedactSubtitle: Bool {
        UserDefaults.standard.bool(
            forKey: PreferenceKeys.notilogRedactSubtitle
        )
    }

    static var notilogRedactBody: Bool {
        UserDefaults.standard.bool(
            forKey: PreferenceKeys.notilogRedactBody
        )
    }

    static var notilogRedactionPolicy: RedactionPolicy {
        makeNotilogRedactionPolicy(
            enabled: notilogRedactionEnabled,
            redactTitle: notilogRedactTitle,
            redactSubtitle: notilogRedactSubtitle,
            redactBody: notilogRedactBody
        )
    }

    static func makeNotilogRedactionPolicy(
        enabled: Bool,
        redactTitle: Bool,
        redactSubtitle: Bool,
        redactBody: Bool
    ) -> RedactionPolicy {
        guard enabled else {
            return .disabled
        }

        var fields: Set<RedactionField> = []

        if redactTitle {
            fields.insert(.title)
        }

        if redactSubtitle {
            fields.insert(.subtitle)
        }

        if redactBody {
            fields.insert(.body)
        }

        return RedactionPolicy(fields: fields)
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
    static func enforceMenuBarOnly() {
        NSApplication.shared.setActivationPolicy(
            .accessory
        )
    }
}

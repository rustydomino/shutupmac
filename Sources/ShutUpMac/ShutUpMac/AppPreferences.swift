import Foundation
import AppKit

enum PreferenceKeys {
    static let hideDockIcon = "hideDockIcon"
    static let enableGlobalHotkeys = "enableGlobalHotkeys"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.hideDockIcon: true,
            PreferenceKeys.enableGlobalHotkeys: true
        ])
    }

    static var hideDockIcon: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.hideDockIcon)
    }

    static var enableGlobalHotkeys: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.enableGlobalHotkeys)
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

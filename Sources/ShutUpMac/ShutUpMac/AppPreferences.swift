import Foundation
import AppKit

enum PreferenceKeys {
    static let hideDockIcon = "hideDockIcon"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PreferenceKeys.hideDockIcon: true
        ])
    }

    static var hideDockIcon: Bool {
        UserDefaults.standard.bool(forKey: PreferenceKeys.hideDockIcon)
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

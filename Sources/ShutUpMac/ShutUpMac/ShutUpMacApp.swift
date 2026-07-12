import SwiftUI
import AppKit

@main
struct ShutUpMacApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        HotKeyManager.shared.registerHotKey()
    }

    var body: some Scene {
        MenuBarExtra("ShutUpMac", systemImage: "bell.slash") {
            Button("Clear Notifications Now") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    NotificationClearer.clear()
                }
            }

            Divider()

            Button("Quit ShutUpMac") {
                NSApplication.shared.terminate(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

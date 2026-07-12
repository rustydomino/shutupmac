import SwiftUI
import AppKit

@main
struct ShutUpMacApp: App {
    init() {
        AppPreferences.registerDefaults()
        DockIconController.apply(hideDockIcon: AppPreferences.hideDockIcon)
        HotKeyController.shared.start()
        TestNotificationSender.shared.start()
    }

    var body: some Scene {
        MenuBarExtra("ShutUpMac", systemImage: "bell.slash") {
            ShutUpMacMenu()
        }
        .menuBarExtraStyle(.menu)

        Window("ShutUpMac Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
    }
}

struct ShutUpMacMenu: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Clear Notifications Now") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationClearer.clear()
            }
        }
        Button("Send Test Notification") {
            TestNotificationSender.shared.sendTestNotification()
        }
        
        Divider()

        Button("Settings…") {
            openWindow(id: "settings")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit ShutUpMac") {
            NSApplication.shared.terminate(nil)
        }
    }
}

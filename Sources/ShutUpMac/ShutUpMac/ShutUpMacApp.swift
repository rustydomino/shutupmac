import SwiftUI
import AppKit

@main
struct ShutUpMacApp: App {
    init() {
        AppPreferences.registerDefaults()
        DockIconController.apply(hideDockIcon: AppPreferences.hideDockIcon)

        TestNotificationSender.shared.start()

        if AppPreferences.enableGlobalHotkeys {
            HotKeyController.shared.start()
        }
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

        Window("About ShutUpMac", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}

struct ShutUpMacMenu: View {
    @Environment(\.openWindow) private var openWindow

    @AppStorage(PreferenceKeys.clearNotificationsHotKey) private var clearNotificationsHotKey = HotKey.defaultClear.encodedString
    @AppStorage(PreferenceKeys.testNotificationHotKey) private var testNotificationHotKey = HotKey.defaultTestNotification.encodedString

    private var clearNotificationsHotKeyDisplay: String {
        (HotKey.decode(clearNotificationsHotKey) ?? .defaultClear).displayString
    }

    private var testNotificationHotKeyDisplay: String {
        (HotKey.decode(testNotificationHotKey) ?? .defaultTestNotification).displayString
    }

    var body: some View {
        Button("Clear Notifications Now  \(clearNotificationsHotKeyDisplay)") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NotificationClearer.clear()
            }
        }

        Button("Send Test Notification  \(testNotificationHotKeyDisplay)") {
            TestNotificationSender.shared.sendTestNotification()
        }

        Divider()

        Button("About ShutUpMac") {
            openWindow(id: "about")

            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)

                if let aboutWindow = NSApplication.shared.windows.first(where: { window in
                    window.title == "About ShutUpMac"
                }) {
                    aboutWindow.makeKeyAndOrderFront(nil)
                    aboutWindow.orderFrontRegardless()
                }
            }
        }

        Button("Settings…") {
            openWindow(id: "settings")

            DispatchQueue.main.async {
                NSApplication.shared.activate(ignoringOtherApps: true)

                if let settingsWindow = NSApplication.shared.windows.first(where: { window in
                    window.title == "ShutUpMac Settings"
                }) {
                    settingsWindow.makeKeyAndOrderFront(nil)
                    settingsWindow.orderFrontRegardless()
                }
            }
        }

        Divider()

        Button("Quit ShutUpMac") {
            NSApplication.shared.terminate(nil)
        }
    }
}

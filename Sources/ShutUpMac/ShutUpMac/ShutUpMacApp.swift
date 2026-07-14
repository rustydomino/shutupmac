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
        MenuBarExtra("ShutUpMac", image: "MenuBarIcon") {
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

    var body: some View {

        // MARK: - Notification Actions Menu

        Button("Clear Visible Notifications") {
            print("GUI menu: Clear Visible Notifications clicked")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("GUI menu: calling NotificationClearer.clearVisible()")
                NotificationClearer.clearVisible()
            }
        }

        Button("Clear All Notifications") {
            print("GUI menu: Clear All Notifications clicked")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("GUI menu: calling NotificationClearer.clearAll()")
                NotificationClearer.clearAll()
            }
        }

        Divider()

        Button("Send Test Notification") {
            print("GUI menu: Send Test Notification clicked")
            TestNotificationSender.shared.sendTestNotification()
        }

        // MARK: - End Notification Actions Menu

        Divider()

        // MARK: - App Menu

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

        // MARK: - End App Menu
    }
}

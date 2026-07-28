import SwiftUI
import AppKit

@main
struct ShutUpMacApp: App {
    @NSApplicationDelegateAdaptor(
        ShutUpMacApplicationDelegate.self
    )
    private var applicationDelegate

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

        Window("ShutUpMac Activity", id: "activity") {
            ActivityView(
                store: applicationDelegate.activityStore
            )
        }
        .defaultSize(width: 760, height: 500)
        
    Window("ShutUpMac Settings", id: "settings") {
        SettingsView(
            automationConfigurationStore:
                applicationDelegate
                    .automationConfigurationStore,
                
                saveAutomationConfiguration: { candidate in
                    applicationDelegate
                        .saveAutomationConfiguration(
                            candidate
                        )
                },
                reloadAutomationConfiguration: {
                    applicationDelegate
                        .reloadAutomationConfiguration()
                },
                setNotilogDatabaseLoggingEnabled: {
                        enabled,
                        completion in

                        applicationDelegate
                            .setNotilogDatabaseLoggingEnabled(
                                enabled,
                                completion: completion
                            )
                }

        )
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

    @AppStorage(PreferenceKeys.enableGlobalHotkeys)
    private var enableGlobalHotkeys = true

    @AppStorage(PreferenceKeys.clearMostRecentNotificationHotKey)
    private var clearMostRecentNotificationHotKey = HotKey.defaultClearMostRecent.encodedString

    @AppStorage(PreferenceKeys.clearVisibleNotificationsHotKey)
    private var clearVisibleNotificationsHotKey = HotKey.defaultClearDesktop.encodedString

    @AppStorage(PreferenceKeys.clearAllNotificationsHotKey)
    private var clearAllNotificationsHotKey = HotKey.defaultClearAll.encodedString

    @AppStorage(PreferenceKeys.testNotificationHotKey)
    private var testNotificationHotKey = HotKey.defaultTestNotification.encodedString

    private var clearMostRecentMenuHotKey: HotKey? {
        guard enableGlobalHotkeys else {
            return nil
        }

        return HotKey.decode(clearMostRecentNotificationHotKey) ?? .defaultClearMostRecent
    }

    private var clearVisibleMenuHotKey: HotKey? {
        guard enableGlobalHotkeys else {
            return nil
        }

        return HotKey.decode(clearVisibleNotificationsHotKey) ?? .defaultClearDesktop
    }

    private var clearAllMenuHotKey: HotKey? {
        guard enableGlobalHotkeys else {
            return nil
        }

        return HotKey.decode(clearAllNotificationsHotKey) ?? .defaultClearAll
    }

    private var testNotificationMenuHotKey: HotKey? {
        guard enableGlobalHotkeys else {
            return nil
        }

        return HotKey.decode(testNotificationHotKey) ?? .defaultTestNotification
    }

    var body: some View {
        Button("Clear Most Recent Notification") {
            print("GUI menu: Clear Most Recent Notification clicked")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("GUI menu: calling NotificationClearer.clearMostRecent()")
                NotificationClearer.clearMostRecent()
            }
        }
        .menuKeyboardShortcut(clearMostRecentMenuHotKey)

        Button("Clear Desktop Notifications") {
            print("GUI menu: Clear Desktop Notifications clicked")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("GUI menu: calling NotificationClearer.clearVisible()")
                NotificationClearer.clearVisible()
            }
        }
        .menuKeyboardShortcut(clearVisibleMenuHotKey)

        Button("Clear All Notifications") {
            print("GUI menu: Clear All Notifications clicked")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("GUI menu: calling NotificationClearer.clearAll()")
                NotificationClearer.clearAll()
            }
        }
        .menuKeyboardShortcut(clearAllMenuHotKey)

        Divider()

        Button("Send Test Notification") {
            sendTestNotificationFromMenu()
        }
        .menuKeyboardShortcut(testNotificationMenuHotKey)

        Divider()

        Button("Activity…") {
            showActivityWindow()
        }
        .keyboardShortcut("1", modifiers: [.command])
        
        Button("Settings…") {
            showSettingsWindow()
        }
        .keyboardShortcut(",", modifiers: [.command])

        Button("About ShutUpMac") {
            showAboutWindow()
        }

        Divider()

        Button("Quit ShutUpMac") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }

    private func showActivityWindow() {
        openWindow(id: "activity")

        DispatchQueue.main.async {
            NSApplication.shared.activate(
                ignoringOtherApps: true
            )

            if let activityWindow =
                NSApplication.shared.windows.first(
                    where: { window in
                        window.title == "ShutUpMac Activity"
                    }
                ) {
                activityWindow.makeKeyAndOrderFront(nil)
                activityWindow.orderFrontRegardless()
            }
        }
    }
    
    private func showSettingsWindow() {
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

    private func showAboutWindow() {
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

    private func sendTestNotificationFromMenu() {
        print("GUI menu: Send Test Notification clicked")

        TestNotificationSender.shared.sendTestNotificationResult { result in
            print(result.message)

            guard !result.didSchedule else {
                return
            }

            showTestNotificationError(message: result.message)
        }
    }

    private func showTestNotificationError(message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Send Test Notification"
        alert.informativeText = message
        alert.addButton(withTitle: "Open Notification Settings")
        alert.addButton(withTitle: "OK")

        let response = alert.runModal()

        guard response == .alertFirstButtonReturn else {
            return
        }

        openNotificationSettings()
    }

    private func openNotificationSettings() {
        let notificationsPath = "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        let bundleID = Bundle.main.bundleIdentifier ?? ""

        if let appSpecificURL = URL(string: "\(notificationsPath)?id=\(bundleID)"),
           NSWorkspace.shared.open(appSpecificURL) {
            return
        }

        if let genericURL = URL(string: notificationsPath) {
            NSWorkspace.shared.open(genericURL)
        }
    }
}

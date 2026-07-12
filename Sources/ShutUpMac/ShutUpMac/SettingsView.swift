import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(PreferenceKeys.hideDockIcon) private var hideDockIcon = true
    @AppStorage(PreferenceKeys.enableGlobalHotkeys) private var enableGlobalHotkeys = true
    @AppStorage(PreferenceKeys.clearNotificationsHotKey) private var clearNotificationsHotKey = HotKeyChoice.controlOptionCommandD.rawValue
    @AppStorage(PreferenceKeys.testNotificationHotKey) private var testNotificationHotKey = HotKeyChoice.controlOptionCommandS.rawValue

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled

    private var duplicateHotkeysSelected: Bool {
        clearNotificationsHotKey != HotKeyChoice.disabled.rawValue &&
        testNotificationHotKey != HotKeyChoice.disabled.rawValue &&
        clearNotificationsHotKey == testNotificationHotKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ShutUpMac Settings")
                .font(.title2)
                .bold()

            Toggle("Hide Dock icon", isOn: $hideDockIcon)

            Text("When enabled, ShutUpMac runs as a menu-bar-only app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Enable global hotkeys", isOn: $enableGlobalHotkeys)

            VStack(alignment: .leading, spacing: 8) {
                Picker("Clear Notifications:", selection: $clearNotificationsHotKey) {
                    ForEach(HotKeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }

                Picker("Send Test Notification:", selection: $testNotificationHotKey) {
                    ForEach(HotKeyChoice.allCases) { choice in
                        Text(choice.displayName).tag(choice.rawValue)
                    }
                }
            }
            .disabled(!enableGlobalHotkeys)

            if duplicateHotkeysSelected {
                Text("Both actions use the same hotkey. The test notification hotkey will not be registered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose global hotkeys for ShutUpMac actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Launch at login", isOn: $launchAtLogin)

            Text("Start ShutUpMac automatically when you log in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if LaunchAtLoginController.status == .requiresApproval {
                Button("Open Login Items Settings…") {
                    LaunchAtLoginController.openLoginItemsSettings()
                }

                Text("macOS needs you to approve ShutUpMac in Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 500, height: 420)
        .onAppear {
            launchAtLogin = LaunchAtLoginController.isEnabled
        }
        .onChange(of: hideDockIcon) { _, newValue in
            DockIconController.apply(hideDockIcon: newValue)
        }
        .onChange(of: enableGlobalHotkeys) { _, newValue in
            if newValue {
                HotKeyController.shared.start()
            } else {
                HotKeyController.shared.stop()
            }
        }
        .onChange(of: clearNotificationsHotKey) { _, _ in
            HotKeyController.shared.restart()
        }
        .onChange(of: testNotificationHotKey) { _, _ in
            HotKeyController.shared.restart()
        }
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginController.setEnabled(newValue)

            if LaunchAtLoginController.status == .requiresApproval {
                LaunchAtLoginController.openLoginItemsSettings()
            }

            launchAtLogin = LaunchAtLoginController.isEnabled
        }
    }
}

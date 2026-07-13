import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @AppStorage(PreferenceKeys.hideDockIcon) private var hideDockIcon = true
    @AppStorage(PreferenceKeys.enableGlobalHotkeys) private var enableGlobalHotkeys = true
    @AppStorage(PreferenceKeys.clearNotificationsHotKey) private var clearNotificationsHotKey = HotKey.defaultClear.encodedString
    @AppStorage(PreferenceKeys.testNotificationHotKey) private var testNotificationHotKey = HotKey.defaultTestNotification.encodedString

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var cliInstallCommand = CLIInstallCommandBuilder.makeCommand()
    @State private var dockIconChangeNeedsRestart = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Toggle("Hide Dock icon", isOn: $hideDockIcon)

            Text("When enabled, ShutUpMac runs as a menu-bar-only app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if dockIconChangeNeedsRestart {
                Text("The Dock icon will be hidden the next time ShutUpMac launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Enable global hotkeys", isOn: $enableGlobalHotkeys)

            VStack(alignment: .leading, spacing: 10) {
                HotKeyRecorderView(
                    title: "Clear Notifications:",
                    encodedHotKey: $clearNotificationsHotKey,
                    defaultHotKey: .defaultClear,
                    otherEncodedHotKey: testNotificationHotKey,
                    onChange: {
                        HotKeyController.shared.restart()
                    },
                    onRecordingStarted: {
                        HotKeyController.shared.stop()
                    },
                    onRecordingEnded: {
                        HotKeyController.shared.restart()
                    }
                )

                HotKeyRecorderView(
                    title: "Send Test Notification:",
                    encodedHotKey: $testNotificationHotKey,
                    defaultHotKey: .defaultTestNotification,
                    otherEncodedHotKey: clearNotificationsHotKey,
                    onChange: {
                        HotKeyController.shared.restart()
                    },
                    onRecordingStarted: {
                        HotKeyController.shared.stop()
                    },
                    onRecordingEnded: {
                        HotKeyController.shared.restart()
                    }
                )
            }
            .disabled(!enableGlobalHotkeys)

            Text("Click a shortcut field, then press a new shortcut. Shortcuts must use at least two of Control, Option, and Command.")
                .font(.caption)
                .foregroundStyle(.secondary)

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

            Divider()

            Text("Command Line Tool")
                .font(.headline)

            Text("""
            Copy and paste the text below to a Terminal prompt to install a symlink to the bundled shutupmac-cli helper. You can edit the text if you prefer a different install location or command name, maybe like stfu. Note: ~/.local/bin must be in your PATH to run shutupmac-cli directly.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $cliInstallCommand)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .border(.secondary.opacity(0.3))

            HStack {
                Button("Reset Command") {
                    cliInstallCommand = CLIInstallCommandBuilder.makeCommand()
                }

                Button("Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cliInstallCommand, forType: .string)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 560, height: 620)
        .onAppear {
            launchAtLogin = LaunchAtLoginController.isEnabled
        }
        .onChange(of: hideDockIcon) { _, newValue in
            if newValue {
                // Going from regular app back to menu-bar-only mode is visually janky
                // if applied while Settings is open. Save the preference now and apply
                // it cleanly at next launch from ShutUpMacApp.init().
                dockIconChangeNeedsRestart = true
            } else {
                // Showing the Dock icon is safe to apply immediately.
                dockIconChangeNeedsRestart = false
                DockIconController.apply(hideDockIcon: false)
            }
        }
        .onChange(of: enableGlobalHotkeys) { _, newValue in
            if newValue {
                HotKeyController.shared.start()
            } else {
                HotKeyController.shared.stop()
            }
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

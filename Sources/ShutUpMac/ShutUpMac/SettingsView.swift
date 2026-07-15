import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @AppStorage(PreferenceKeys.hideDockIcon) private var hideDockIcon = true
    @AppStorage(PreferenceKeys.enableGlobalHotkeys) private var enableGlobalHotkeys = true
    @AppStorage(PreferenceKeys.clearVisibleNotificationsHotKey) private var clearVisibleNotificationsHotKey = HotKey.defaultClearDesktop.encodedString
    @AppStorage(PreferenceKeys.clearAllNotificationsHotKey) private var clearAllNotificationsHotKey = HotKey.defaultClearAll.encodedString
    @AppStorage(PreferenceKeys.testNotificationHotKey) private var testNotificationHotKey = HotKey.defaultTestNotification.encodedString

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var cliInstallCommand = CLIInstallCommandBuilder.makeCommand()
    @State private var dockIconChangeNeedsRestart = false

    private var showDockIcon: Binding<Bool> {
        Binding(
            get: {
                !hideDockIcon
            },
            set: { newValue in
                hideDockIcon = !newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Toggle("Show Dock icon", isOn: showDockIcon)

            Text("When enabled, ShutUpMac appears in the Dock and app switcher like a regular Mac app. When disabled, it runs as a menu-bar-only utility.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if dockIconChangeNeedsRestart {
                Text("ShutUpMac will return to menu-bar-only mode the next time it launches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Enable global hotkeys", isOn: $enableGlobalHotkeys)

            VStack(alignment: .leading, spacing: 10) {
                HotKeyRecorderView(
                    title: "Clear Desktop Notifications:",
                    encodedHotKey: $clearVisibleNotificationsHotKey,
                    defaultHotKey: .defaultClearDesktop,
                    otherEncodedHotKeys: [
                        clearAllNotificationsHotKey,
                        testNotificationHotKey
                    ],
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
                    title: "Clear All Notifications:",
                    encodedHotKey: $clearAllNotificationsHotKey,
                    defaultHotKey: .defaultClearAll,
                    otherEncodedHotKeys: [
                        clearVisibleNotificationsHotKey,
                        testNotificationHotKey
                    ],
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
                    otherEncodedHotKeys: [
                        clearVisibleNotificationsHotKey,
                        clearAllNotificationsHotKey
                    ],
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
        .frame(width: 620, height: 660)
        .onAppear {
            launchAtLogin = LaunchAtLoginController.isEnabled
        }
        .onChange(of: hideDockIcon) { _, newValue in
            if newValue {
                // Turning off "Show Dock icon" moves the app back to menu-bar-only mode.
                // Applying that while Settings is open is visually janky, so save the
                // preference now and apply it cleanly at next launch from ShutUpMacApp.init().
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

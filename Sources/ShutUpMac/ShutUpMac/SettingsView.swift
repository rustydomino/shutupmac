import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @AppStorage(PreferenceKeys.hideDockIcon) private var hideDockIcon = true
    @AppStorage(PreferenceKeys.enableGlobalHotkeys) private var enableGlobalHotkeys = true

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled

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

            Text("Ctrl-Option-Command-D clears notifications. Ctrl-Option-Command-S sends a test notification.")
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

            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 320)
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
        .onChange(of: launchAtLogin) { _, newValue in
            LaunchAtLoginController.setEnabled(newValue)

            if LaunchAtLoginController.status == .requiresApproval {
                LaunchAtLoginController.openLoginItemsSettings()
            }

            launchAtLogin = LaunchAtLoginController.isEnabled
        }
    }
}

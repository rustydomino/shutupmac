import SwiftUI

struct SettingsView: View {
    @AppStorage(PreferenceKeys.hideDockIcon) private var hideDockIcon = true
    @AppStorage(PreferenceKeys.enableGlobalHotkeys) private var enableGlobalHotkeys = true

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

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 230)
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
    }
}

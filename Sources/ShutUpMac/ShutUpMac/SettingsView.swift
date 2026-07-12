import SwiftUI

struct SettingsView: View {
    @AppStorage(PreferenceKeys.hideDockIcon) private var hideDockIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("ShutUpMac Settings")
                .font(.title2)
                .bold()

            Toggle("Hide Dock icon", isOn: $hideDockIcon)

            Text("When enabled, ShutUpMac runs as a menu-bar-only app.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(width: 360, height: 150)
        .onChange(of: hideDockIcon) { _, newValue in
            DockIconController.apply(hideDockIcon: newValue)
        }
    }
}

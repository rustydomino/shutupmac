import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Debug"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "bell.slash")
                .font(.system(size: 48))

            Text("ShutUpMac")
                .font(.title)
                .bold()

            Text("Version \(appVersion) (\(buildNumber))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Quickly clear macOS Notification Center notifications from the menu bar, global hotkey, or command line.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(.init("© 2026 Mike Chao ([mike@kodada.net](mailto:mike@kodada.net))."))
                    .fixedSize(horizontal: false, vertical: true)

                Text(.init("ShutUpMac is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License version 2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html), as published by the [Free Software Foundation](https://www.fsf.org/)."))
                    .fixedSize(horizontal: false, vertical: true)

                Text("ShutUpMac is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.")
                    .fixedSize(horizontal: false, vertical: true)

                Text(.init("See the [GNU General Public License version 2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html) for details."))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(24)
        .frame(width: 420, height: 420)
    }
}

import SwiftUI
import ServiceManagement
import NotilogCore

struct SettingsView: View {
    let setNotilogDatabaseLoggingEnabled:
        (
            Bool,
            @escaping @MainActor @Sendable (
                DatabaseLoggingUpdateResult
            ) -> Void
        ) -> Void

    let replaceNotilogRedactionPolicy:
        (RedactionPolicy) -> Void

    @AppStorage(PreferenceKeys.notilogRedactionEnabled)
    private var notilogRedactionEnabled = false

    @AppStorage(PreferenceKeys.notilogRedactTitle)
    private var notilogRedactTitle = true

    @AppStorage(PreferenceKeys.notilogRedactSubtitle)
    private var notilogRedactSubtitle = true

    @AppStorage(PreferenceKeys.notilogRedactBody)
    private var notilogRedactBody = true

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled

    @State private var databaseLoggingEnabled =
        AppPreferences.notilogDatabaseLoggingEnabled

    @State private var databaseLoggingUpdateInProgress =
        false

    @State private var databaseLoggingErrorMessage:
        String?

    private var databaseLoggingBinding:
        Binding<Bool> {

        Binding(
            get: {
                databaseLoggingEnabled
            },
            set: { requestedValue in
                guard !databaseLoggingUpdateInProgress else {
                    return
                }

                databaseLoggingUpdateInProgress = true
                databaseLoggingErrorMessage = nil

                setNotilogDatabaseLoggingEnabled(
                    requestedValue
                ) { result in
                    databaseLoggingUpdateInProgress = false

                    switch result {
                    case .updated(let activeValue):
                        databaseLoggingEnabled =
                            activeValue

                    case .failed(let message):
                        databaseLoggingErrorMessage =
                            message
                    }
                }
            }
        )
    }

private var redactionEnabledBinding:
    Binding<Bool> {

    Binding(
        get: {
            notilogRedactionEnabled
        },
        set: { enabled in
            if enabled
                && !notilogRedactTitle
                && !notilogRedactSubtitle
                && !notilogRedactBody {

                notilogRedactTitle = true
                notilogRedactSubtitle = true
                notilogRedactBody = true
            }

            notilogRedactionEnabled = enabled
            applyRedactionPolicy()
        }
    )
}

private var redactTitleBinding:
    Binding<Bool> {

    Binding(
        get: {
            notilogRedactTitle
        },
        set: { enabled in
            guard enabled
                || notilogRedactSubtitle
                || notilogRedactBody else {

                return
            }

            notilogRedactTitle = enabled
            applyRedactionPolicy()
        }
    )
}

private var redactSubtitleBinding:
    Binding<Bool> {

    Binding(
        get: {
            notilogRedactSubtitle
        },
        set: { enabled in
            guard enabled
                || notilogRedactTitle
                || notilogRedactBody else {

                return
            }

            notilogRedactSubtitle = enabled
            applyRedactionPolicy()
        }
    )
}

    private var redactBodyBinding:
        Binding<Bool> {

        Binding(
            get: {
                notilogRedactBody
            },
            set: { enabled in
                guard enabled
                    || notilogRedactTitle
                    || notilogRedactSubtitle else {

                    return
                }

                notilogRedactBody = enabled
                applyRedactionPolicy()
            }
        )
    }

    private func applyRedactionPolicy() {
        replaceNotilogRedactionPolicy(
            AppPreferences.notilogRedactionPolicy
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {


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

            Text("Notification History")
                .font(.headline)

            Toggle(
                "Enable notification logging",
                isOn: databaseLoggingBinding
            )
            .disabled(databaseLoggingUpdateInProgress)

            Text(
                "When disabled, rules and actions still work, "
                + "but new notifications are neither written "
                + "to the Notilog database nor shown in Activity. "
                + "Existing history is retained and remains visible."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    "Redact notification contents",
                    isOn: redactionEnabledBinding
                )

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "Title",
                        isOn: redactTitleBinding
                    )

                    Toggle(
                        "Subtitle",
                        isOn: redactSubtitleBinding
                    )

                    Toggle(
                        "Body",
                        isOn: redactBodyBinding
                    )
                }
                .padding(.leading, 20)
                .disabled(!notilogRedactionEnabled)

                Text(
                    "Selected fields are replaced with "
                    + "\"[REDACTED]\" before being written "
                    + "to notification history."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
            }
            .disabled(
                !databaseLoggingEnabled
                    || databaseLoggingUpdateInProgress
            )
            .opacity(
                databaseLoggingEnabled
                    && !databaseLoggingUpdateInProgress
                    ? 1
                    : 0.5
            )

            if databaseLoggingUpdateInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Updating notification logging…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let databaseLoggingErrorMessage {
                Text(databaseLoggingErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
            }


        }
        .padding(24)
        .frame(
            maxWidth: 620,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .top
        )
        .onAppear {
            launchAtLogin =
                LaunchAtLoginController.isEnabled

            databaseLoggingEnabled =
                AppPreferences
                    .notilogDatabaseLoggingEnabled
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

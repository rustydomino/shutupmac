import SwiftUI
import ServiceManagement
import AppKit
import NotilogCore

struct SettingsView: View {
    @ObservedObject
    var automationConfigurationStore:
        AutomationConfigurationStore

    let saveAutomationConfiguration:
        (AutomationConfig) -> Void 

    let reloadAutomationConfiguration:
        () -> Void

    let setNotilogDatabaseLoggingEnabled:
        (
            Bool,
            @escaping @MainActor @Sendable (
                DatabaseLoggingUpdateResult
            ) -> Void
        ) -> Void

    let setNotilogRulesAutoDismissEnabled:
        (Bool) -> Void

    let replaceNotilogRedactionPolicy:
        (RedactionPolicy) -> Void

    @AppStorage(PreferenceKeys.enableGlobalHotkeys)
    private var enableGlobalHotkeys = true

    @AppStorage(PreferenceKeys.clearMostRecentNotificationHotKey)
    private var clearMostRecentNotificationHotKey =
        HotKey.defaultClearMostRecent.encodedString

    @AppStorage(PreferenceKeys.clearVisibleNotificationsHotKey)
    private var clearVisibleNotificationsHotKey =
        HotKey.defaultClearDesktop.encodedString

    @AppStorage(PreferenceKeys.clearAllNotificationsHotKey)
    private var clearAllNotificationsHotKey =
        HotKey.defaultClearAll.encodedString

    @AppStorage(PreferenceKeys.testNotificationHotKey)
    private var testNotificationHotKey = 
        HotKey.defaultTestNotification.encodedString

    @AppStorage(
        PreferenceKeys.notilogRulesAutoDismissEnabled
    )
    private var notilogRulesAutoDismissEnabled = true


    @AppStorage(PreferenceKeys.notilogRedactionEnabled)
    private var notilogRedactionEnabled = false

    @AppStorage(PreferenceKeys.notilogRedactTitle)
    private var notilogRedactTitle = true

    @AppStorage(PreferenceKeys.notilogRedactSubtitle)
    private var notilogRedactSubtitle = true

    @AppStorage(PreferenceKeys.notilogRedactBody)
    private var notilogRedactBody = true

    @State private var launchAtLogin = LaunchAtLoginController.isEnabled
    @State private var cliInstallCommand = CLIInstallCommandBuilder.makeCommand()

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


            Toggle("Enable global hotkeys", isOn: $enableGlobalHotkeys)

            VStack(alignment: .leading, spacing: 10) {
                HotKeyRecorderView(
                    title: "Clear Most Recent Notification:",
                    encodedHotKey: $clearMostRecentNotificationHotKey,
                    defaultHotKey: .defaultClearMostRecent,
                    otherEncodedHotKeys: [
                        clearVisibleNotificationsHotKey,
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
                    title: "Clear Desktop Notifications:",
                    encodedHotKey: $clearVisibleNotificationsHotKey,
                    defaultHotKey: .defaultClearDesktop,
                    otherEncodedHotKeys: [
                        clearMostRecentNotificationHotKey,
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
                        clearMostRecentNotificationHotKey,
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
                        clearMostRecentNotificationHotKey,
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


            Divider()

            Text("Automation Configuration")
                .font(.headline)

            Toggle(
                "Enable rules-based auto-dismiss",
                isOn: $notilogRulesAutoDismissEnabled
            )

            Text(
                "When disabled, notification monitoring and "
                + "history logging continue, but configured "
                + "dismissal rules do not run."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )

            Text(
                automationConfigurationStore.configURL.path
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            Button("Reload config.json") {
                reloadAutomationConfiguration()
            }

            Text(
                "Reloads rules from disk and activates them immediately. "
                + "If the file is invalid, the currently active rules remain unchanged."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if let errorMessage =
                automationConfigurationStore.errorMessage {

                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )
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
        .frame(width: 620, height: 860)
        .onAppear {
            launchAtLogin =
                LaunchAtLoginController.isEnabled

            databaseLoggingEnabled =
                AppPreferences
                    .notilogDatabaseLoggingEnabled
        }
        .onAppear {
            launchAtLogin =
                LaunchAtLoginController.isEnabled

            databaseLoggingEnabled =
                AppPreferences
                    .notilogDatabaseLoggingEnabled
        }
        .onChange(
            of: notilogRulesAutoDismissEnabled
        ) { _, enabled in
            setNotilogRulesAutoDismissEnabled(
                enabled
            )
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

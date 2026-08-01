import SwiftUI

struct HotKeySettingsView: View {
    @AppStorage(PreferenceKeys.enableGlobalHotkeys)
    private var enableGlobalHotkeys = true

    @AppStorage(
        PreferenceKeys.clearMostRecentNotificationHotKey
    )
    private var clearMostRecentNotificationHotKey =
        HotKey.defaultClearMostRecent.encodedString

    @AppStorage(
        PreferenceKeys.clearVisibleNotificationsHotKey
    )
    private var clearVisibleNotificationsHotKey =
        HotKey.defaultClearDesktop.encodedString

    @AppStorage(
        PreferenceKeys.clearAllNotificationsHotKey
    )
    private var clearAllNotificationsHotKey =
        HotKey.defaultClearAll.encodedString

    @AppStorage(
        PreferenceKeys.testNotificationHotKey
    )
    private var testNotificationHotKey =
        HotKey.defaultTestNotification.encodedString

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(
                "Enable global hotkeys",
                isOn: $enableGlobalHotkeys
            )

            VStack(alignment: .leading, spacing: 10) {
                HotKeyRecorderView(
                    title:
                        "Clear Most Recent Notification:",
                    encodedHotKey:
                        $clearMostRecentNotificationHotKey,
                    defaultHotKey:
                        .defaultClearMostRecent,
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
                    title:
                        "Clear Desktop Notifications:",
                    encodedHotKey:
                        $clearVisibleNotificationsHotKey,
                    defaultHotKey:
                        .defaultClearDesktop,
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
                    title:
                        "Clear All Notifications:",
                    encodedHotKey:
                        $clearAllNotificationsHotKey,
                    defaultHotKey:
                        .defaultClearAll,
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
                    title:
                        "Send Test Notification:",
                    encodedHotKey:
                        $testNotificationHotKey,
                    defaultHotKey:
                        .defaultTestNotification,
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

            Text(
                "Click a shortcut field, then press a new "
                    + "shortcut. Shortcuts must use at least "
                    + "two of Control, Option, and Command."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal: false,
                vertical: true
            )

            Spacer()
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
        .onChange(
            of: enableGlobalHotkeys
        ) { _, enabled in
            if enabled {
                HotKeyController.shared.start()
            } else {
                HotKeyController.shared.stop()
            }
        }
    }
}
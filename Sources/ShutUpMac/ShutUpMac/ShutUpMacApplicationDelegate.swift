import AppKit
import NotilogCore

@MainActor
final class ShutUpMacApplicationDelegate: NSObject, NSApplicationDelegate {
    let activityStore = ActivityStore()

    private let runtimePaths =
        NotilogRuntimePaths.legacyNotilogDefault()

    private(set) lazy var automationConfigurationStore =
        AutomationConfigurationStore(
            configURL: runtimePaths.config
        )

    private lazy var notilogMonitoringController =
        NotilogMonitoringController(
            runtimePaths: runtimePaths,
            initialConfiguration:
                automationConfigurationStore.configuration,
            loggingEnabled:
                AppPreferences
                    .notilogDatabaseLoggingEnabled,
            redactionPolicy:
                AppPreferences
                    .notilogRedactionPolicy,
            automationMode:
                AppPreferences
                    .notilogRulesAutoDismissEnabled
                    ? .runActions
                    : .disabled,
            dismissalHandler: { notificationKey in
                guard let key = NotificationAXKey(
                    rawValue: notificationKey
                ) else {
                    return NotificationDismissalResult(
                        succeeded: false,
                        message:
                            "Invalid notification AX key: "
                            + notificationKey,
                        exitCode: 1
                    )
                }

                let result =
                    ShutUpMac
                        .dismissVisibleNotificationResult(
                            matching: key
                        )

                return NotificationDismissalResult(
                    succeeded:
                        result.succeeded && result.didClear,
                    message: result.message,
                    exitCode: result.exitCode
                )
            },
            onHistoricalRecords: { [weak self] records in                
                self?.activityStore.loadHistoricalRecords(
                    records
                )
            },
            onActivityItems: { [weak self] activityItems in
                self?.activityStore.append(
                    activityItems
                )
            },
            onMonitoringError: { [weak self] message in
                if let message {
                    self?.activityStore.reportMonitoringError(
                        message
                    )
                } else {
                    self?.activityStore.clearMonitoringError()
                }
            }
        )
    func saveAutomationConfiguration(
        _ candidate: AutomationConfig
    ) {
        automationConfigurationStore.saveAndActivate(
            candidate,
            using: notilogMonitoringController
        )
    }

    func reloadAutomationConfiguration() {
        automationConfigurationStore.reloadFromDisk(
            using: notilogMonitoringController
        )
    }

    func setNotilogDatabaseLoggingEnabled(
        _ enabled: Bool,
        completion: @escaping
            @MainActor @Sendable (
                DatabaseLoggingUpdateResult
            ) -> Void
    ) {
        notilogMonitoringController.setLoggingEnabled(
            enabled
        ) { result in
            switch result {
            case .updated(let activeValue):
                AppPreferences
                    .setNotilogDatabaseLoggingEnabled(
                        activeValue
                    )

            case .failed:
                break
            }

            completion(result)
        }
    }

    func setNotilogRulesAutoDismissEnabled(
        _ enabled: Bool
    ) {
        notilogMonitoringController
            .setRulesAutomationEnabled(
                enabled
            )
    }

    func replaceNotilogRedactionPolicy(
        _ policy: RedactionPolicy
    ) {
        notilogMonitoringController
            .replaceRedactionPolicy(policy)
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        let isAccessibilityTrusted =
            AccessibilityPermission.isTrusted(prompt: true)

        print(
            "Notilog monitoring Accessibility trusted: "
            + "\(isAccessibilityTrusted)"
        )

        guard isAccessibilityTrusted else {
            print(
                "Notilog monitoring was not started because "
                + "Accessibility permission is unavailable."
            )
            return
        }

        guard automationConfigurationStore.load() != nil else {
            print(
                "Notilog monitoring was not started because "
                + "config.json could not be loaded: "
                + (
                    automationConfigurationStore.errorMessage
                        ?? "Unknown configuration error"
                )
            )

            return
        }

        notilogMonitoringController.start()
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        notilogMonitoringController.stop()
    }
}

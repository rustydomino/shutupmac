import AppKit
import NotilogCore

@MainActor
final class ShutUpMacApplicationDelegate: NSObject, NSApplicationDelegate {
    let activityStore = ActivityStore()

    private let runtimePaths =
        NotilogRuntimePaths.legacyNotilogDefault()

    private var hasRequestedNotilogMonitoringStart = false

    private(set) lazy var automationConfigurationStore =
        AutomationConfigurationStore(
            configURL: runtimePaths.config
        )

    private(set) lazy var retentionConfigurationStore =
        RetentionConfigurationStore(
            fileURL: runtimePaths.retention
        )

    private(set) lazy var retentionConfiguration:
        RetentionConfiguration = {
            do {
                return try AppPreferences
                    .migratedNotilogRetentionConfiguration(
                        using: retentionConfigurationStore
                    )
            } catch {
                let errorDetail: String

                if let notilogError =
                    error as? NotilogError
                {
                    errorDetail =
                        notilogError.errorDescription
                            ?? String(
                                describing: notilogError
                            )
                } else {
                    errorDetail =
                        error.localizedDescription
                }

                activityStore.reportMonitoringError(
                    MonitoringErrorPresentation(
                        title:
                        "Retention configuration error",
                        detail:
                        "Could not load retention.json; " +
                            "using built-in defaults. " +
                            errorDetail
                    )
                )

                return RetentionConfiguration.defaults
            }
        }()

    private lazy var notilogMonitoringController =
        NotilogMonitoringController(
            runtimePaths: runtimePaths,
            retentionConfigurationStore:
            retentionConfigurationStore,
            initialConfiguration:
            automationConfigurationStore.configuration,
            loggingEnabled:
            AppPreferences
                .notilogDatabaseLoggingEnabled,
            notificationEventLimit:
            retentionConfiguration
                .notificationEventLimit,
            actionRunLimit:
            retentionConfiguration
                .actionRunLimit,
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
            onMonitoringError: { [weak self] presentation in
                if let presentation {
                    self?.activityStore.reportMonitoringError(
                        presentation
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
            case let .updated(activeValue):
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

    func requestDatabaseStatistics(
        completion: @escaping
        @MainActor @Sendable (
            DatabaseStatisticsResult
        ) -> Void
    ) {
        notilogMonitoringController
            .requestDatabaseStatistics(
                completion: completion
            )
    }

    func resetActivityDatabase(
        completion: @escaping
        @MainActor @Sendable (
            ActivityDatabaseResetResult
        ) -> Void
    ) {
        notilogMonitoringController
            .resetActivityDatabase(
                completion: completion
            )
    }

    func updateRetentionLimits(
        notificationEventLimit: Int,
        actionRunLimit: Int,
        completion: @escaping
        @MainActor @Sendable (
            RetentionLimitsUpdateResult
        ) -> Void
    ) {
        notilogMonitoringController
            .updateRetentionLimits(
                notificationEventLimit:
                notificationEventLimit,
                actionRunLimit:
                actionRunLimit,
                completion: completion
            )
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
        _: Notification
    ) {
        startNotilogMonitoringIfPossible(
            promptForAccessibility: true
        )
    }

    func applicationDidBecomeActive(
        _: Notification
    ) {
        startNotilogMonitoringIfPossible(
            promptForAccessibility: false
        )
    }

    private func startNotilogMonitoringIfPossible(
        promptForAccessibility: Bool
    ) {
        guard !hasRequestedNotilogMonitoringStart else {
            return
        }

        let isAccessibilityTrusted =
            AccessibilityPermission.isTrusted(
                prompt: promptForAccessibility
            )

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

        hasRequestedNotilogMonitoringStart = true
        notilogMonitoringController.start()
    }

    func applicationWillTerminate(
        _: Notification
    ) {
        notilogMonitoringController.stop()
    }
}

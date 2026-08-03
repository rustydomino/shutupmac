import Foundation
import NotilogCore
import OSLog

enum AutomationConfigurationUpdateResult:
    Sendable
{
    case activated
    case failed(String)
}

enum DatabaseLoggingUpdateResult:
    Sendable
{
    case updated(Bool)
    case failed(String)
}

enum DatabaseStatisticsResult:
    Sendable
{
    case loaded(
        NotificationStoreStatistics?
    )

    case failed(String)
}

enum ActivityDatabaseResetResult:
    Sendable
{
    case reset
    case failed(String)
}

enum RetentionLimitsUpdateResult:
    Sendable
{
    case updated
    case failed(String)
}

struct MonitoringErrorPresentation:
    Equatable,
    Sendable
{
    let title: String
    let detail: String
}

protocol AutomationConfigurationActivating:
    Sendable
{
    func replaceAutomationConfiguration(
        _ configuration: AutomationConfig,
        completion: @escaping
        @MainActor @Sendable (
            AutomationConfigurationUpdateResult
        ) -> Void
    )
}

/// Schedules Notilog monitoring cycles on one private serial queue.
///
/// The runtime is created, used, and destroyed on this queue so that scans
/// cannot overlap and the database connection remains queue-confined.
final nonisolated class NotilogMonitoringController:
    AutomationConfigurationActivating,
    @unchecked Sendable
{
    private static let logger = Logger(
        subsystem: "net.kodada.mike.ShutUpMac",
        category: "NotilogMonitoring"
    )

    private static func errorPresentation(
        prefix: String,
        error: Error
    ) -> MonitoringErrorPresentation {
        let title: String

        switch error {
        case NotilogError.monitorAlreadyRunning:
            title = "Monitoring already running"

        case NotilogError.monitoringLockOpenFailed,
             NotilogError.monitoringLockFailed:
            title = "Monitoring lock error"

        case NotilogError.databaseNotFound:
            title = "Activity database not found"

        case NotilogError.schemaRequiresMigration:
            title = "Activity database needs migration"

        case NotilogError.schemaTooNew:
            title = "Activity database is newer"

        case NotilogError.unrecognizedLegacySchema:
            title = "Activity database not recognized"

        case NotilogError.invalidRetentionConfiguration:
            title = "Invalid retention settings"

        case NotilogError.readOnlyMutation:
            title = "Activity database is read-only"

        case NotilogError.databaseOpenFailed,
             NotilogError.databaseCreateSchemaFailed,
             NotilogError.databasePrepareFailed,
             NotilogError.databaseQueryFailed,
             NotilogError.databaseInsertFailed,
             NotilogError.databaseUpdateFailed,
             NotilogError.databaseDeleteFailed,
             NotilogError.databaseMigrationFailed:
            title = "Activity database error"

        default:
            title = "Monitoring error"
        }

        let errorDetail: String

        if let notilogError = error as? NotilogError {
            errorDetail =
                notilogError.errorDescription
                    ?? String(describing: notilogError)
        } else {
            errorDetail = error.localizedDescription
        }

        return MonitoringErrorPresentation(
            title: title,
            detail: "\(prefix): \(errorDetail)"
        )
    }

    private let queue = DispatchQueue(
        label: "com.shutupmac.notilog-monitoring"
    )

    private let interval: TimeInterval
    private let runtimePaths: NotilogRuntimePaths

    private let retentionConfigurationStore:
        RetentionConfigurationStore

    private var automationMode:
        AutomationExecutionMode

    private let dismissalHandler:
        NotificationDismissalHandler?

    private var loggingEnabled: Bool

    private var notificationEventLimit: Int
    private var actionRunLimit: Int

    private var redactionPolicy: RedactionPolicy

    private let initialConfiguration:
        AutomationConfig?

    private let onActivityItems:
        @MainActor @Sendable ([ActivityItem]) -> Void

    private let onHistoricalRecords:
        @MainActor @Sendable (
            [NotificationActivityRecord]
        ) -> Void

    private let onMonitoringError:
        @MainActor @Sendable (
            MonitoringErrorPresentation?
        ) -> Void

    private var timer: DispatchSourceTimer?
    private var runtime: NotilogMonitoringRuntime?
    private var isStarted = false

    private var historyErrorPresentation:
        MonitoringErrorPresentation?
    private var cycleErrorActive = false

    init(
        runtimePaths: NotilogRuntimePaths =
            .legacyNotilogDefault(),
        retentionConfigurationStore:
        RetentionConfigurationStore? = nil,
        initialConfiguration:
        AutomationConfig? = nil,
        loggingEnabled: Bool = true,
        notificationEventLimit: Int =
            NotificationStore.defaultNotificationEventLimit,
        actionRunLimit: Int =
            NotificationStore.defaultActionRunLimit,
        redactionPolicy: RedactionPolicy = .disabled,
        automationMode:
        AutomationExecutionMode = .disabled,
        dismissalHandler:
        NotificationDismissalHandler? = nil,
        interval: TimeInterval = 1.0,
        onHistoricalRecords: @escaping
        @MainActor @Sendable (
            [NotificationActivityRecord]
        ) -> Void,
        onActivityItems: @escaping
        @MainActor @Sendable ([ActivityItem]) -> Void,
        onMonitoringError: @escaping
        @MainActor @Sendable (
            MonitoringErrorPresentation?
        ) -> Void = { _ in }
    ) {
        self.runtimePaths = runtimePaths
        self.retentionConfigurationStore =
            retentionConfigurationStore
                ?? RetentionConfigurationStore(
                    fileURL: runtimePaths.retention
                )
        self.initialConfiguration =
            initialConfiguration
        self.loggingEnabled = loggingEnabled

        self.notificationEventLimit =
            notificationEventLimit
        self.actionRunLimit = actionRunLimit

        self.redactionPolicy = redactionPolicy
        self.automationMode = automationMode
        self.dismissalHandler = dismissalHandler
        self.interval = interval
        self.onHistoricalRecords = onHistoricalRecords
        self.onActivityItems = onActivityItems
        self.onMonitoringError = onMonitoringError
    }

    func start() {
        queue.async { [weak self] in
            guard let self, !self.isStarted else {
                return
            }

            do {
                let runtime = try NotilogMonitoringRuntime(
                    runtimePaths: self.runtimePaths,
                    initialConfiguration:
                    self.initialConfiguration,
                    loggingEnabled:
                    self.loggingEnabled,
                    notificationEventLimit:
                    self.notificationEventLimit,
                    actionRunLimit:
                    self.actionRunLimit,
                    redactionPolicy:
                    self.redactionPolicy,
                    automationMode:
                    self.automationMode,
                    dismissalHandler:
                    self.dismissalHandler
                )

                do {
                    let historicalEvents =
                        try runtime.recentAppearanceEvents(
                            limit: 1000
                        )

                    let historicalRecords =
                        historicalEvents.map { record in
                            let notification =
                                record.event.notification

                            return NotificationActivityRecord(
                                historicalNotification:
                                ActivityNotificationSnapshot(
                                    key: notification.key,
                                    app: notification.app,
                                    title: notification.title,
                                    subtitle: notification.subtitle,
                                    body: notification.body
                                ),
                                appearedAt: record.event.timestamp
                            )
                        }

                    self.historyErrorPresentation = nil

                    Task {
                        @MainActor [
                            onHistoricalRecords,
                            onMonitoringError,
                            historicalRecords
                        ] in
                        onHistoricalRecords(
                            historicalRecords
                        )

                        onMonitoringError(nil)
                    }
                } catch {
                    let presentation =
                        Self.errorPresentation(
                            prefix:
                            "Could not load Notilog activity history",
                            error: error
                        )

                    self.historyErrorPresentation =
                        presentation

                    Self.logger.error(
                        "\(presentation.detail, privacy: .public)"
                    )

                    Task {
                        @MainActor [
                            onMonitoringError =
                            self.onMonitoringError,
                            presentation
                        ] in
                        onMonitoringError(presentation)
                    }
                }

                let timer = DispatchSource.makeTimerSource(
                    queue: self.queue
                )

                timer.schedule(
                    deadline: .now(),
                    repeating: self.interval,
                    leeway: .milliseconds(100)
                )

                timer.setEventHandler { [weak self] in
                    self?.processCycle()
                }

                self.runtime = runtime
                self.timer = timer
                self.isStarted = true

                timer.resume()
                print("Notilog monitoring started")
            } catch {
                let presentation =
                    Self.errorPresentation(
                        prefix:
                        "Could not start Notilog monitoring",
                        error: error
                    )

                Self.logger.error(
                    "\(presentation.detail, privacy: .public)"
                )

                Task {
                    @MainActor [
                        onMonitoringError =
                        self.onMonitoringError,
                        presentation
                    ] in
                    onMonitoringError(presentation)
                }
            }
        }
    }

    func stop() {
        queue.sync {
            guard isStarted else {
                return
            }

            timer?.setEventHandler {}
            timer?.cancel()

            timer = nil
            runtime = nil
            isStarted = false

            print("Notilog monitoring stopped")
        }
    }

    func requestDatabaseStatistics(
        completion: @escaping
        @MainActor @Sendable (
            DatabaseStatisticsResult
        ) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let runtime = self.runtime else {
                Task { @MainActor in
                    completion(
                        .failed(
                            "Notilog monitoring is not running."
                        )
                    )
                }

                return
            }

            do {
                let statistics =
                    try runtime.databaseStatistics()

                Task {
                    @MainActor [
                        completion,
                        statistics
                    ] in
                    completion(
                        .loaded(statistics)
                    )
                }
            } catch {
                let message =
                    "Could not load database statistics: "
                        + String(describing: error)

                Self.logger.error(
                    "\(message, privacy: .public)"
                )

                Task {
                    @MainActor [
                        completion,
                        message
                    ] in
                    completion(
                        .failed(message)
                    )
                }
            }
        }
    }

    func resetActivityDatabase(
        completion: @escaping
        @MainActor @Sendable (
            ActivityDatabaseResetResult
        ) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let runtime = self.runtime else {
                Task { @MainActor in
                    completion(
                        .failed(
                            "Notilog monitoring is not running."
                        )
                    )
                }

                return
            }

            do {
                try runtime.resetDatabase()

                self.historyErrorPresentation = nil
                self.cycleErrorActive = false

                Task {
                    @MainActor [
                        onHistoricalRecords =
                            self.onHistoricalRecords,
                        onMonitoringError =
                            self.onMonitoringError,
                        completion
                    ] in
                        onHistoricalRecords([])
                        onMonitoringError(nil)
                        completion(.reset)
                }
            } catch {
                let presentation =
                    Self.errorPresentation(
                        prefix:
                        "Could not reset the Activity database",
                        error: error
                    )

                Self.logger.error(
                    "\(presentation.detail, privacy: .public)"
                )

                Task {
                    @MainActor [
                        onMonitoringError =
                        self.onMonitoringError,
                        completion,
                        presentation
                    ] in
                    onMonitoringError(presentation)

                    completion(
                        .failed(presentation.detail)
                    )
                }
            }
        }
    }

    func updateRetentionLimits(
        notificationEventLimit: Int,
        actionRunLimit: Int,
        completion: @escaping
        @MainActor @Sendable (
            RetentionLimitsUpdateResult
        ) -> Void
    ) {
        guard AppPreferences
            .notificationEventRetentionRange
            .contains(notificationEventLimit)
        else {
            Task { @MainActor in
                completion(
                    .failed(
                        "Activity event retention must be between "
                            + "\(AppPreferences.notificationEventRetentionRange.lowerBound.formatted()) "
                            + "and "
                            + "\(AppPreferences.notificationEventRetentionRange.upperBound.formatted())."
                    )
                )
            }

            return
        }

        guard AppPreferences
            .actionRunRetentionRange
            .contains(actionRunLimit)
        else {
            Task { @MainActor in
                completion(
                    .failed(
                        "Action-run retention must be between "
                            + "\(AppPreferences.actionRunRetentionRange.lowerBound.formatted()) "
                            + "and "
                            + "\(AppPreferences.actionRunRetentionRange.upperBound.formatted())."
                    )
                )
            }

            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let runtime = self.runtime else {
                Task { @MainActor in
                    completion(
                        .failed(
                            "Notilog monitoring is not running."
                        )
                    )
                }

                return
            }

            do {
                let configuration =
                    try RetentionConfiguration(
                        notificationEventLimit:
                            notificationEventLimit,
                        actionRunLimit:
                            actionRunLimit
                    )

                try self.retentionConfigurationStore.save(
                    configuration
                )

                try runtime.updateRetentionLimits(
                    notificationEventLimit:
                        configuration
                            .notificationEventLimit,
                    actionRunLimit:
                        configuration
                            .actionRunLimit
                )

                self.notificationEventLimit =
                    configuration
                        .notificationEventLimit

                self.actionRunLimit =
                    configuration
                        .actionRunLimit

                Task { @MainActor in
                    completion(.updated)
                }
            } catch {
                let message =
                    "Could not update retention limits: "
                        + String(describing: error)

                Self.logger.error(
                    "\(message, privacy: .public)"
                )

                Task { @MainActor in
                    completion(
                        .failed(message)
                    )
                }
            }
        }
    }

    func setRulesAutomationEnabled(
        _ enabled: Bool
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let automationMode:
                AutomationExecutionMode =
                enabled
                    ? .runActions
                    : .disabled

            self.automationMode = automationMode

            self.runtime?
                .setRulesAutomationEnabled(
                    enabled
                )

            print(
                "Notilog rules automation "
                    + (
                        enabled
                            ? "enabled"
                            : "disabled"
                    )
            )
        }
    }

    func replaceAutomationEngine(
        _ engine: AutomationEngine
    ) {
        queue.async { [weak self, engine] in
            guard let self else {
                return
            }

            guard let runtime = self.runtime else {
                print(
                    "Could not replace Notilog automation engine: "
                        + "monitoring is not running"
                )
                return
            }

            runtime.replaceAutomationEngine(
                engine
            )

            print(
                "Notilog automation engine replaced"
            )
        }
    }

    func replaceAutomationConfiguration(
        _ configuration: AutomationConfig,
        completion: @escaping
        @MainActor @Sendable (
            AutomationConfigurationUpdateResult
        ) -> Void
    ) {
        queue.async {
            [weak self, configuration, completion] in
            guard let self else {
                return
            }

            guard let runtime = self.runtime else {
                Task { @MainActor in
                    completion(
                        .failed(
                            "Notilog monitoring is not running"
                        )
                    )
                }

                return
            }

            do {
                try runtime.replaceAutomationConfiguration(
                    configuration
                )

                Task { @MainActor in
                    completion(.activated)
                }
            } catch {
                let message = String(
                    describing: error
                )

                Task { @MainActor in
                    completion(
                        .failed(message)
                    )
                }
            }
        }
    }

    func setLoggingEnabled(
        _ enabled: Bool,
        completion: @escaping
        @MainActor @Sendable (
            DatabaseLoggingUpdateResult
        ) -> Void
    ) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let runtime = self.runtime else {
                Task { @MainActor in
                    completion(
                        .failed(
                            "Notilog monitoring is not running"
                        )
                    )
                }

                return
            }

            do {
                try runtime.setLoggingEnabled(
                    enabled
                )

                self.loggingEnabled = enabled

                Task { @MainActor in
                    completion(
                        .updated(enabled)
                    )
                }
            } catch {
                let message = String(
                    describing: error
                )

                Task { @MainActor in
                    completion(
                        .failed(message)
                    )
                }
            }
        }
    }

    func replaceRedactionPolicy(
        _ policy: RedactionPolicy
    ) {
        queue.async { [weak self, policy] in
            guard let self else {
                return
            }

            // Retain the setting even if monitoring is not currently running.
            self.redactionPolicy = policy

            guard let runtime = self.runtime else {
                return
            }

            runtime.replaceRedactionPolicy(
                policy
            )

            print(
                "Notilog redaction policy replaced"
            )
        }
    }

    private func processCycle() {
        guard let runtime else {
            return
        }

        do {
            let timestamp = Date()

            let result = try runtime.processOneCycle(
                at: timestamp
            )

            if cycleErrorActive {
                cycleErrorActive = false

                let presentation =
                    historyErrorPresentation

                Task {
                    @MainActor [
                        onMonitoringError,
                        presentation
                    ] in
                    onMonitoringError(presentation)
                }
            }

            let activityItems = ActivityItemFactory.makeItems(
                from: result,
                verificationTimestamp: timestamp,
                redactionPolicy: redactionPolicy
            )

            guard !activityItems.isEmpty else {
                return
            }

            // Rules and actions still execute while logging is disabled,
            // but notification activity is not published to the Activity viewer.
            guard loggingEnabled else {
                return
            }

            Task { @MainActor [onActivityItems, activityItems] in
                onActivityItems(activityItems)
            }

            print(
                "Notilog monitoring cycle produced "
                    + "\(activityItems.count) activity item(s)"
            )
        } catch {
            cycleErrorActive = true

            let presentation =
                Self.errorPresentation(
                    prefix:
                    "Notilog monitoring cycle failed",
                    error: error
                )

            Self.logger.error(
                "\(presentation.detail, privacy: .public)"
            )

            Task {
                @MainActor [
                    onMonitoringError,
                    presentation
                ] in
                onMonitoringError(presentation)
            }
        }
    }
}

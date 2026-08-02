import Foundation
import NotilogCore
import OSLog

enum AutomationConfigurationUpdateResult:
    Sendable {
    case activated
    case failed(String)
}

enum DatabaseLoggingUpdateResult:
    Sendable {
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

protocol AutomationConfigurationActivating:
    Sendable {

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
nonisolated final class NotilogMonitoringController:
    AutomationConfigurationActivating,
    @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "net.kodada.mike.ShutUpMac",
        category: "NotilogMonitoring"
    )

    private let queue = DispatchQueue(
        label: "com.shutupmac.notilog-monitoring"
    )

    private let interval: TimeInterval
    private let runtimePaths: NotilogRuntimePaths
    
    private var automationMode:
        AutomationExecutionMode

    private let dismissalHandler:
        NotificationDismissalHandler?

    private var loggingEnabled: Bool
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
        @MainActor @Sendable (String?) -> Void

    private var timer: DispatchSourceTimer?
    private var runtime: NotilogMonitoringRuntime?
    private var isStarted = false

    private var historyErrorMessage: String?
    private var cycleErrorActive = false

    init(
        runtimePaths: NotilogRuntimePaths =
            .legacyNotilogDefault(),
        initialConfiguration:
            AutomationConfig? = nil,
        loggingEnabled: Bool = true,
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
            @MainActor @Sendable (String?) -> Void = { _ in }
    ) {        
        self.runtimePaths = runtimePaths
        self.initialConfiguration =
            initialConfiguration
        self.loggingEnabled = loggingEnabled
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
                            limit: 1_000
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

                    self.historyErrorMessage = nil

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
                    let message =
                        "Could not load Notilog activity history: "
                        + String(describing: error)

                    self.historyErrorMessage = message

                    Self.logger.error(
                        "\(message, privacy: .public)"
                    )

                    Task {
                        @MainActor [
                            onMonitoringError,
                            message
                        ] in
                            onMonitoringError(message)
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
                let message =
                    "Could not start Notilog monitoring: "
                    + String(describing: error)

                Self.logger.error(
                    "\(message, privacy: .public)"
                )

                Task {
                    @MainActor [
                        onMonitoringError = self.onMonitoringError,
                        message
                    ] in
                        onMonitoringError(message)
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

                self.historyErrorMessage = nil
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
                let message =
                    "Could not reset the Activity database: "
                    + String(describing: error)

                Self.logger.error(
                    "\(message, privacy: .public)"
                )

                Task {
                    @MainActor [
                        onMonitoringError =
                            self.onMonitoringError,
                        completion,
                        message
                    ] in
                        onMonitoringError(message)
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

                let message = historyErrorMessage

                Task {
                    @MainActor [
                        onMonitoringError,
                        message
                    ] in
                        onMonitoringError(message)
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

            let message =
                "Notilog monitoring cycle failed: "
                + String(describing: error)

            Self.logger.error(
                "\(message, privacy: .public)"
            )

            Task {
                @MainActor [
                    onMonitoringError,
                    message
                ] in
                    onMonitoringError(message)
            }
        }
    }
}

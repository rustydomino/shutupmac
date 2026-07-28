import Foundation
import NotilogCore

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
    private let queue = DispatchQueue(
        label: "com.shutupmac.notilog-monitoring"
    )

    private let interval: TimeInterval
    private let runtimePaths: NotilogRuntimePaths
    
    private var loggingEnabled: Bool

    private let initialConfiguration:
        AutomationConfig?

    private let onActivityItems:
        @MainActor @Sendable ([ActivityItem]) -> Void
    
    private let onHistoricalRecords:
        @MainActor @Sendable (
            [NotificationActivityRecord]
        ) -> Void

    private var timer: DispatchSourceTimer?
    private var runtime: NotilogMonitoringRuntime?
    private var isStarted = false

    init(
        runtimePaths: NotilogRuntimePaths =
            .legacyNotilogDefault(),
        initialConfiguration:
            AutomationConfig? = nil,
        loggingEnabled: Bool = true,
        interval: TimeInterval = 1.0,
        onHistoricalRecords: @escaping
            @MainActor @Sendable (
                [NotificationActivityRecord]
            ) -> Void,
        onActivityItems: @escaping
            @MainActor @Sendable ([ActivityItem]) -> Void
    ) {
        self.runtimePaths = runtimePaths
        self.initialConfiguration =
            initialConfiguration
        self.loggingEnabled = loggingEnabled
        self.interval = interval
        self.onHistoricalRecords = onHistoricalRecords
        self.onActivityItems = onActivityItems
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
                        self.loggingEnabled
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

                    Task {
                        @MainActor [
                            onHistoricalRecords,
                            historicalRecords
                        ] in
                            onHistoricalRecords(
                                historicalRecords
                            )
                    }
                } catch {
                    print(
                        "Could not load Notilog activity history: "
                        + "\(error)"
                    )
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
                print(
                    "Could not start Notilog monitoring: \(error)"
                )
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

    private func processCycle() {
        guard let runtime else {
            return
        }

        do {
            let timestamp = Date()

            let result = try runtime.processOneCycle(
                at: timestamp
            )

            let activityItems = ActivityItemFactory.makeItems(
                from: result,
                verificationTimestamp: timestamp
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
            print(
                "Notilog monitoring cycle failed: \(error)"
            )
        }
    }
}

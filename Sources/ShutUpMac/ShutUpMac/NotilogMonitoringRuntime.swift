import Foundation
import NotilogCore

/// Owns the Notilog objects used by the ShutUpMac app.
///
/// This class processes one monitoring cycle at a time. Scheduling and
/// cancellation remain the responsibility of the app-host lifecycle.
nonisolated final class NotilogMonitoringRuntime {
    let runtimePaths: NotilogRuntimePaths

    private let scanner: NotificationScanner
    private let store: NotificationStore
    private let session: ObservationSession
    private let monitor: NotificationMonitor

    init(
        runtimePaths: NotilogRuntimePaths = .legacyNotilogDefault(),
        redactionPolicy: RedactionPolicy = .disabled,
        automationMode: AutomationExecutionMode = .disabled,
        dismissalVerificationDelay: TimeInterval = 2.0
    ) throws {
        try runtimePaths.ensureDirectoriesExist()

        let scanner = NotificationScanner()

        let store = try NotificationStore(
            path: runtimePaths.database.path
        )

        let previouslyActive = try store.loadActiveNotifications()

        let automationEngine = try Self.loadAutomationEngine(
            configURL: runtimePaths.config
        )

        let automationProcessor = NotificationAutomationProcessor(
            engine: automationEngine
        )

        let session = ObservationSession()

        let cycleProcessor = MonitoringCycleProcessor(
            previouslyActive: previouslyActive
        )

        let completedVerificationCoordinator =
            CompletedActionVerificationCoordinator(
                store: store
            )

        let actionResultCoordinator = ActionResultCoordinator(
            store: store,
            session: session,
            redactionPolicy: redactionPolicy,
            cycleProcessor: cycleProcessor,
            dismissalVerificationDelay: dismissalVerificationDelay
        )

        let eventPersistenceCoordinator =
            NotificationEventPersistenceCoordinator(
                store: store,
                session: session,
                redactionPolicy: redactionPolicy
            )

        let eventCoordinator = NotificationEventCoordinator(
            persistenceCoordinator: eventPersistenceCoordinator,
            automationProcessor: automationProcessor,
            actionResultCoordinator: actionResultCoordinator
        )

        let monitor = NotificationMonitor(
            cycleProcessor: cycleProcessor,
            completedVerificationCoordinator:
                completedVerificationCoordinator,
            eventCoordinator: eventCoordinator,
            automationMode: automationMode
        )

        self.runtimePaths = runtimePaths
        self.scanner = scanner
        self.store = store
        self.session = session
        self.monitor = monitor

        try store.startSession(session)
    }

    deinit {
        try? store.endSession(session)
    }

    /// Scans the current Notification Center AX tree and processes exactly
    /// one monitoring cycle.
    func processOneCycle(
        at timestamp: Date,
        actionTimestampProvider: () -> Date = { Date() }
    ) throws -> NotificationMonitoringResult {
        let notifications = scanner.scan()

        return try monitor.processScan(
            notifications: notifications,
            at: timestamp,
            actionTimestampProvider: actionTimestampProvider,
            afterCompletedActionVerifications: { _ in },
            beforeAutomation: { _ in },
            beforeActionResultCoordination: { _ in },
            afterRecoveredEvents: { _ in }
        )
    }

    private static func loadAutomationEngine(
        configURL: URL
    ) throws -> AutomationEngine {
        guard FileManager.default.fileExists(
            atPath: configURL.path
        ) else {
            return AutomationEngine(rules: [])
        }

        let config = try AutomationConfig.load(
            from: configURL
        )

        return AutomationEngine(
            rules: try config.notificationRules()
        )
    }
}

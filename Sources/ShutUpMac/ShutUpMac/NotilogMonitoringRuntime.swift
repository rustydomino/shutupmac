import Foundation
import NotilogCore

/// Owns the Notilog objects used by the ShutUpMac app.
///
/// This class processes one monitoring cycle at a time. Scheduling and
/// cancellation remain the responsibility of the app-host lifecycle.
nonisolated final class NotilogMonitoringRuntime {
    let runtimePaths: NotilogRuntimePaths

    private let monitoringProcessLock:
        MonitoringProcessLock

    private let scanner: NotificationScanner

    private var store: NotificationStore?
    private var session: ObservationSession
    private var loggingEnabled: Bool

    private let automationProcessor:
        NotificationAutomationProcessor

    private let completedVerificationCoordinator:
        CompletedActionVerificationCoordinator

    private let actionResultCoordinator:
        ActionResultCoordinator

    private let eventPersistenceCoordinator:
        NotificationEventPersistenceCoordinator

    private let monitor: NotificationMonitor

    init(
        runtimePaths: NotilogRuntimePaths = .legacyNotilogDefault(),
        initialConfiguration: AutomationConfig? = nil,
        loggingEnabled: Bool = true,
        redactionPolicy: RedactionPolicy = .disabled,
        automationMode: AutomationExecutionMode = .disabled,
        dismissalHandler: NotificationDismissalHandler? = nil,
        dismissalVerificationDelay: TimeInterval = 2.0
    ) throws {
        try runtimePaths.ensureDirectoriesExist()

        let monitoringProcessLock =
            try MonitoringProcessLock(
                lockFileURL: runtimePaths.monitorLock
            )

        let scanner = NotificationScanner()

        let store: NotificationStore?

        let databaseAlreadyExists =
            FileManager.default.fileExists(
                atPath: runtimePaths.database.path
            )

        if loggingEnabled || databaseAlreadyExists {
            store = try NotificationStore(
                path: runtimePaths.database.path
            )
        } else {
            store = nil
        }

        let previouslyActive =
            try store?.loadActiveNotifications()
                ?? []

        let automationEngine: AutomationEngine

        if let initialConfiguration {
            automationEngine = AutomationEngine(
                rules: try initialConfiguration.notificationRules()
            )
        } else {
            automationEngine = try Self.loadAutomationEngine(
                configURL: runtimePaths.config
            )
        }

        let actionRunner = ActionRunner(
            dismissalHandler: dismissalHandler
        )

        let automationProcessor = NotificationAutomationProcessor(
            engine: automationEngine,
            runner: actionRunner
        )

        let session = ObservationSession()

        let cycleProcessor = MonitoringCycleProcessor(
            previouslyActive: previouslyActive
        )

        // The database may remain open for reading existing history
        // while new persistence is disabled.
        let persistenceStore =
            loggingEnabled ? store : nil

        let completedVerificationCoordinator =
            CompletedActionVerificationCoordinator(
                store: persistenceStore
            )


        let actionResultCoordinator = ActionResultCoordinator(
            store: persistenceStore,
            session: session,
            redactionPolicy: redactionPolicy,
            cycleProcessor: cycleProcessor,
            dismissalVerificationDelay: dismissalVerificationDelay
        )

        let eventPersistenceCoordinator =
            NotificationEventPersistenceCoordinator(
                store: persistenceStore,
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
        self.monitoringProcessLock =
            monitoringProcessLock
        self.scanner = scanner
        self.store = store
        self.session = session
        self.loggingEnabled = loggingEnabled
        self.automationProcessor =
            automationProcessor
        self.completedVerificationCoordinator =
            completedVerificationCoordinator
        self.actionResultCoordinator =
            actionResultCoordinator
        self.eventPersistenceCoordinator =
            eventPersistenceCoordinator
        self.monitor = monitor

        if loggingEnabled,
        let store {
            try store.startSession(session)
        }

    }

deinit {
    if loggingEnabled,
       let store {
        try? store.endSession(session)
    }
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

    /// Replaces the rules used by subsequent monitoring cycles.
    ///
    /// The caller is responsible for invoking this on the same serial queue
    /// used for processOneCycle().
    func replaceAutomationEngine(
        _ engine: AutomationEngine
    ) {
        automationProcessor.replaceEngine(
            engine
        )
    }

    /// Enables or disables rule action execution for subsequent cycles.
    ///
    /// Monitoring and persistence continue while automation is disabled.
    /// The caller must invoke this on the same serial queue used for
    /// processOneCycle().
    func setRulesAutomationEnabled(
        _ enabled: Bool
    ) {
        monitor.replaceAutomationMode(
            enabled ? .runActions : .disabled
        )
    }


    /// Replaces the redaction policy used by subsequent database writes.
    ///
    /// The caller must invoke this on the same serial queue used for
    /// processOneCycle().
    func replaceRedactionPolicy(
        _ policy: RedactionPolicy
    ) {
        eventPersistenceCoordinator
            .replaceRedactionPolicy(policy)

        actionResultCoordinator
            .replaceRedactionPolicy(policy)
    }

    /// Enables or disables database persistence for subsequent monitoring cycles.
    ///
    /// The database may remain open while logging is disabled so that existing
    /// history can still be read. The caller must invoke this on the same serial
    /// queue used for processOneCycle().
    func setLoggingEnabled(
        _ enabled: Bool
    ) throws {
        guard enabled != loggingEnabled else {
            return
        }

        if enabled {
            let writableStore: NotificationStore

            if let store {
                // Reuse an existing database that was opened for
                // reading historical records.
                writableStore = store
            } else {
                writableStore = try NotificationStore(
                    path: runtimePaths.database.path
                )
            }

            let candidateSession =
                ObservationSession()

            // Do not connect any coordinator until the new
            // database session has started successfully.
            try writableStore.startSession(
                candidateSession
            )

            completedVerificationCoordinator
                .replaceStore(writableStore)

            actionResultCoordinator
                .replacePersistence(
                    store: writableStore,
                    session: candidateSession
                )

            eventPersistenceCoordinator
                .replacePersistence(
                    store: writableStore,
                    session: candidateSession
                )

            store = writableStore
            session = candidateSession
            loggingEnabled = true
        } else {
            guard let currentStore = store else {
                return
            }

            // If ending the session fails, leave the current
            // persistence configuration unchanged.
            try currentStore.endSession(
                session
            )

            completedVerificationCoordinator
                .replaceStore(nil)

            actionResultCoordinator
                .replacePersistence(
                    store: nil,
                    session: session
                )

            eventPersistenceCoordinator
                .replacePersistence(
                    store: nil,
                    session: session
                )

            // Keep the database open so existing history can
            // still be queried and displayed.
            loggingEnabled = false
        }
    }   

    /// Builds and activates rules from a new configuration.
    ///
    /// The current engine remains active if configuration conversion fails.

    func replaceAutomationConfiguration(
        _ configuration: AutomationConfig
    ) throws {
        try automationProcessor.replaceConfiguration(
            configuration
        )
    }

    /// Loads the most recent persisted notification appearances.
    ///
    /// Results are returned oldest-to-newest so ActivityStore can rebuild
    /// its normal rolling history in chronological order.
    func recentAppearanceEvents(
        limit: Int = 1_000
    ) throws -> [NotificationEventRecord] {
        guard let store else {
            return []
        }

        return try store.recentAppearanceEvents(
            limit: limit
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

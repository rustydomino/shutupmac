import Foundation

public struct NotificationMonitoringResult {
    public let completedActionVerifications:
        [CompletedActionVerification]

    public let recoveredEvents:
        [CoordinatedNotificationEvent]

    public let events:
        [CoordinatedNotificationEvent]

    public init(
        completedActionVerifications:
            [CompletedActionVerification],
        recoveredEvents:
            [CoordinatedNotificationEvent],
        events:
            [CoordinatedNotificationEvent]
    ) {
        self.completedActionVerifications =
            completedActionVerifications

        self.recoveredEvents = recoveredEvents
        self.events = events
    }
}

public final class NotificationMonitor {
    private let cycleProcessor:
        MonitoringCycleProcessor

    private let completedVerificationCoordinator:
        CompletedActionVerificationCoordinator

    private let eventCoordinator:
        NotificationEventCoordinator

    private var automationMode:
        AutomationExecutionMode

    public init(
        cycleProcessor: MonitoringCycleProcessor,
        completedVerificationCoordinator:
            CompletedActionVerificationCoordinator,
        eventCoordinator:
            NotificationEventCoordinator,
        automationMode: AutomationExecutionMode
    ) {
        self.cycleProcessor = cycleProcessor

        self.completedVerificationCoordinator =
            completedVerificationCoordinator

        self.eventCoordinator = eventCoordinator
        self.automationMode = automationMode
    }

    /// Replaces the automation mode used by subsequent scans.
    ///
    /// The caller must synchronize this with processScan().
    public func replaceAutomationMode(
        _ automationMode: AutomationExecutionMode
    ) {
        self.automationMode = automationMode
    }


    public func processScan(
        notifications: [VisibleNotification],
        at timestamp: Date,
        actionTimestampProvider: () -> Date,
        afterCompletedActionVerifications:
            ([CompletedActionVerification]) -> Void,
        beforeAutomation:
            (NotificationEvent) -> Void,
        beforeActionResultCoordination:
            (ActionRunResult) -> Void,
        afterRecoveredEvents:
            ([CoordinatedNotificationEvent]) -> Void
    ) throws -> NotificationMonitoringResult {
        let cycleResult = cycleProcessor.processScan(
            notifications: notifications,
            at: timestamp
        )

        let completedActionVerifications =
            try completedVerificationCoordinator.process(
                cycleResult.completedActionVerifications
            )

        afterCompletedActionVerifications(
            completedActionVerifications
        )

        let recoveredEvents =
            try eventCoordinator.process(
                cycleResult.recoveredEvents,
                automationMode: automationMode,
                actionTimestampProvider:
                    actionTimestampProvider,
                beforeAutomation: beforeAutomation,
                beforeActionResultCoordination:
                    beforeActionResultCoordination
            )

        afterRecoveredEvents(recoveredEvents)

        let events = try eventCoordinator.process(
            cycleResult.events,
            automationMode: automationMode,
            actionTimestampProvider:
                actionTimestampProvider,
            beforeAutomation: beforeAutomation,
            beforeActionResultCoordination:
                beforeActionResultCoordination
        )

        return NotificationMonitoringResult(
            completedActionVerifications:
                completedActionVerifications,
            recoveredEvents: recoveredEvents,
            events: events
        )
    }
}

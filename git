import Foundation

public struct MonitoringCycleResult {
    public let completedActionVerifications: [CompletedActionVerification]
    public let recoveredEvents: [NotificationEvent]
    public let events: [NotificationEvent]

    public init(
        completedActionVerifications: [CompletedActionVerification],
        recoveredEvents: [NotificationEvent],
        events: [NotificationEvent]
    ) {
        self.completedActionVerifications = completedActionVerifications
        self.recoveredEvents = recoveredEvents
        self.events = events
    }
}

public final class MonitoringCycleProcessor {
    private let eventProcessor: NotificationEventProcessor
    private let actionVerificationProcessor: ActionVerificationProcessor

    public init(
        previouslyActive: [VisibleNotification] = [],
        disappearanceGraceScans: Int = 2,
        pendingActionVerifications: [PendingActionVerification] = []
    ) {
        self.eventProcessor = NotificationEventProcessor(
            previouslyActive: previouslyActive,
            disappearanceGraceScans: disappearanceGraceScans
        )

        self.actionVerificationProcessor = ActionVerificationProcessor(
            pendingVerifications: pendingActionVerifications
        )
    }

    public func scheduleActionVerification(
        actionRunID: Int64?,
        notificationKey: String,
        requestedAt timestamp: Date,
        delay: TimeInterval
    ) {
        actionVerificationProcessor.schedule(
            actionRunID: actionRunID,
            notificationKey: notificationKey,
            requestedAt: timestamp,
            delay: delay
        )
    }

    public func processScan(
        notifications: [VisibleNotification],
        at timestamp: Date
    ) -> MonitoringCycleResult {
        let completedActionVerifications =
            actionVerificationProcessor.processDue(
                visibleNotifications: notifications,
                at: timestamp
            )

        let eventResult = eventProcessor.processScan(
            notifications: notifications,
            at: timestamp
        )

        return MonitoringCycleResult(
            completedActionVerifications: completedActionVerifications,
            recoveredEvents: eventResult.recoveredEvents,
            events: eventResult.events
        )
    }
}
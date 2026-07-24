import Foundation

public struct NotificationEventProcessingResult {
    public let recoveredEvents: [NotificationEvent]
    public let events: [NotificationEvent]
}

public final class NotificationEventProcessor {
    private let tracker: NotificationEventTracker
    private let previouslyActive: [VisibleNotification]
    private var didRecoverPreviousState = false

    public init(
        previouslyActive: [VisibleNotification] = [],
        disappearanceGraceScans: Int = 2
    ) {
        self.tracker = NotificationEventTracker(
            disappearanceGraceScans: disappearanceGraceScans
        )
        self.previouslyActive = previouslyActive
    }

    public func processScan(
        notifications: [VisibleNotification],
        at timestamp: Date
    ) -> NotificationEventProcessingResult {
        let snapshot = NotificationSnapshot(
            timestamp: timestamp,
            notifications: notifications
        )

        let recoveredEvents: [NotificationEvent]

        if didRecoverPreviousState {
            recoveredEvents = []
        } else {
            let currentKeys = Set(notifications.map { $0.key })

            recoveredEvents = previouslyActive
                .filter { !currentKeys.contains($0.key) }
                .map {
                    NotificationEvent(
                        type: .disappearedUnobserved,
                        notification: $0,
                        timestamp: timestamp
                    )
                }

            didRecoverPreviousState = true
        }

        let events = tracker.update(with: snapshot)

        return NotificationEventProcessingResult(
            recoveredEvents: recoveredEvents,
            events: events
        )
    }
}
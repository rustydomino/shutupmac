import Foundation
import NotilogCore

/// Converts NotilogCore result types into app-owned, Sendable values.
nonisolated enum ActivityItemFactory {
    static func makeItems(
        from result: NotificationMonitoringResult,
        verificationTimestamp: Date
    ) -> [ActivityItem] {
        let verificationItems =
            result.completedActionVerifications.map {
                makeVerificationItem(
                    from: $0,
                    timestamp: verificationTimestamp
                )
            }

        let recoveredItems =
            result.recoveredEvents.flatMap {
                makeItems(from: $0)
            }

        let eventItems =
            result.events.flatMap {
                makeItems(from: $0)
            }

        return verificationItems
            + recoveredItems
            + eventItems
    }

    private static func makeItems(
        from coordinatedEvent: CoordinatedNotificationEvent
    ) -> [ActivityItem] {
        let eventItem = makeEventItem(
            from: coordinatedEvent.event
        )

        let actionItems =
            coordinatedEvent.actionResults.map {
                makeActionItem(from: $0)
            }

        return [eventItem] + actionItems
    }

    private static func makeEventItem(
        from event: NotificationEvent
    ) -> ActivityItem {
        ActivityItem(
            timestamp: event.timestamp,
            kind: itemKind(for: event.type),
            summary: eventSummary(for: event),
            notification: snapshot(
                from: event.notification
            )
        )
    }

    private static func makeActionItem(
        from coordinatedResult: CoordinatedActionResult
    ) -> ActivityItem {
        let result = coordinatedResult.result

        return ActivityItem(
            timestamp: result.event.timestamp,
            kind: .actionRun,
            summary:
                "\(result.ruleName): "
                + result.resolvedAction.summary,
            detail: result.message,
            notification: snapshot(
                from: result.event.notification
            ),
            ruleName: result.ruleName,
            actionRunID: coordinatedResult.actionRunID,
            status: result.status.rawValue
        )
    }

    private static func makeVerificationItem(
        from verification: CompletedActionVerification,
        timestamp: Date
    ) -> ActivityItem {
        ActivityItem(
            timestamp: timestamp,
            kind: .actionVerification,
            summary: verificationSummary(
                for: verification.status
            ),
            detail:
                "Notification key: "
                + verification.notificationKey,
            actionRunID: verification.actionRunID,
            status: verification.status.rawValue
        )
    }

    private static func snapshot(
        from notification: VisibleNotification
    ) -> ActivityNotificationSnapshot {
        ActivityNotificationSnapshot(
            key: notification.key,
            app: notification.app,
            title: notification.title,
            subtitle: notification.subtitle,
            body: notification.body
        )
    }

    private static func itemKind(
        for eventType: NotificationEventType
    ) -> ActivityItemKind {
        switch eventType {
        case .appeared:
            return .notificationAppeared

        case .disappeared:
            return .notificationDisappeared

        case .disappearedUnobserved:
            return .notificationDisappearedUnobserved
        }
    }

    private static func eventSummary(
        for event: NotificationEvent
    ) -> String {
        let label = notificationLabel(
            event.notification
        )

        switch event.type {
        case .appeared:
            return "Appeared — \(label)"

        case .disappeared:
            return "Disappeared — \(label)"

        case .disappearedUnobserved:
            return "Recovered disappearance — \(label)"
        }
    }

    private static func notificationLabel(
        _ notification: VisibleNotification
    ) -> String {
        let app = notification.app.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let title = notification.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if app.isEmpty && title.isEmpty {
            return "Notification"
        }

        if app.isEmpty {
            return title
        }

        if title.isEmpty {
            return app
        }

        return "\(app): \(title)"
    }

    private static func verificationSummary(
        for status: ActionVerificationStatus
    ) -> String {
        switch status {
        case .pending:
            return "Dismissal verification pending"

        case .probablySucceeded:
            return "Dismissal probably succeeded"

        case .definitelyFailed:
            return "Dismissal definitely failed"
        }
    }
}//
//  ActivityItemFactory.swift
//  ShutUpMac
//
//  Created by mike on 7/24/26.
//


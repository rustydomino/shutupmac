import Foundation

public final class NotificationEventTracker {
    private var previous: [String: VisibleNotification] = [:]
    private var missingCounts: [String: Int] = [:]

    private let disappearanceGraceScans: Int

    public init(disappearanceGraceScans: Int = 2) {
        self.disappearanceGraceScans = disappearanceGraceScans
    }

    public func update(with snapshot: NotificationSnapshot) -> [NotificationEvent] {
        let currentNotifications = snapshot.notifications
        let timestamp = snapshot.timestamp
        let current = Dictionary(uniqueKeysWithValues: currentNotifications.map { ($0.key, $0) })

        var events: [NotificationEvent] = []

        for notification in currentNotifications {
            missingCounts[notification.key] = nil

            if previous[notification.key] == nil {
                events.append(
                    NotificationEvent(
                        type: .appeared,
                        notification: notification,
                        timestamp: timestamp
                    )
                )
            }
        }

        for (key, oldNotification) in previous {
            if current[key] == nil {
                let count = (missingCounts[key] ?? 0) + 1
                missingCounts[key] = count

                if count >= disappearanceGraceScans {
                    events.append(
                        NotificationEvent(
                            type: .disappeared,
                            notification: oldNotification,
                            timestamp: timestamp
                        )
                    )

                    previous[key] = nil
                    missingCounts[key] = nil
                }
            }
        }

        for notification in currentNotifications {
            previous[notification.key] = notification
        }

        return events
    }
}

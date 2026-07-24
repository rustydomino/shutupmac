import Foundation

public struct NotificationSnapshot {
    public let timestamp: Date
    public let notifications: [VisibleNotification]

    public init(timestamp: Date, notifications: [VisibleNotification]) {
        self.timestamp = timestamp
        self.notifications = notifications
    }
}

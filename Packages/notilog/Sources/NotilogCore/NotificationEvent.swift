import Foundation

public enum NotificationEventType: String, Codable {
    case appeared
    case disappeared
    case disappearedUnobserved = "disappeared_unobserved"
}

public struct NotificationEvent {
    public let type: NotificationEventType
    public let notification: VisibleNotification
    public let timestamp: Date

    public init(type: NotificationEventType, notification: VisibleNotification, timestamp: Date) {
        self.type = type
        self.notification = notification
        self.timestamp = timestamp
    }
}

public struct NotificationEventRecord {
    public let id: Int64
    public let sessionID: String
    public let event: NotificationEvent

    public init(id: Int64, sessionID: String, event: NotificationEvent) {
        self.id = id
        self.sessionID = sessionID
        self.event = event
    }
}

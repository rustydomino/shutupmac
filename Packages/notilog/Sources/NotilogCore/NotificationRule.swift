import Foundation

public struct NotificationRule {
    public let id: UUID
    public let name: String
    public let enabled: Bool
    public let criteria: NotificationMatchCriteria
    public let actions: [NotificationAction]

    public init(
        id: UUID,
        name: String,
        enabled: Bool = true,
        criteria: NotificationMatchCriteria,
        actions: [NotificationAction]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.criteria = criteria
        self.actions = actions
    }

    public func matches(_ event: NotificationEvent) -> Bool {
        guard enabled else {
            return false
        }

        return criteria.matches(event)
    }
}

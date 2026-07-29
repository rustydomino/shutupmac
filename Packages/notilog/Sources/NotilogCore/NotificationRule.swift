import Foundation

public struct NotificationRule {
    public let id: UUID
    public let name: String
    public let enabled: Bool
    public let criteria: NotificationMatchCriteria
    public let exceptions: [NotificationException]
    public let actions: [NotificationAction]

    public init(
        id: UUID,
        name: String,
        enabled: Bool = true,
        criteria: NotificationMatchCriteria,
        exceptions: [NotificationException] = [],
        actions: [NotificationAction]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.criteria = criteria
        self.exceptions = exceptions
        self.actions = actions
    }

    public func matches(_ event: NotificationEvent) -> Bool {
        guard enabled,
              criteria.matches(event) else {
            return false
        }

        let hasMatchingException = exceptions.contains {
            exception in

            exception.matches(
                event.notification,
                caseSensitive: criteria.caseSensitive
            )
        }

        return !hasMatchingException
    }

}

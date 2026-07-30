import Foundation

public struct NotificationMatchCriteria {
    public var eventTypes: [NotificationEventType]?

    public var appEquals: String?
    public var appContains: String?

    public var titleEquals: String?
    public var titleContains: String?

    public var subtitleEquals: String?
    public var subtitleContains: String?

    public var bodyEquals: String?
    public var bodyContains: String?

    public var anyTextContains: String?

    public var caseSensitive: Bool

    public init(
        eventTypes: [NotificationEventType]? = nil,
        appEquals: String? = nil,
        appContains: String? = nil,
        titleEquals: String? = nil,
        titleContains: String? = nil,
        subtitleEquals: String? = nil,
        subtitleContains: String? = nil,
        bodyEquals: String? = nil,
        bodyContains: String? = nil,
        anyTextContains: String? = nil,
        caseSensitive: Bool = false
    ) {
        self.eventTypes = eventTypes
        self.appEquals = appEquals
        self.appContains = appContains
        
        self.titleEquals = titleEquals
        self.titleContains = titleContains

        self.subtitleEquals = subtitleEquals
        self.subtitleContains = subtitleContains

        self.bodyEquals = bodyEquals
        self.bodyContains = bodyContains

        self.anyTextContains = anyTextContains
        self.caseSensitive = caseSensitive
    }

    public func matches(_ event: NotificationEvent) -> Bool {
        if let eventTypes, !eventTypes.contains(event.type) {
            return false
        }

        return matches(event.notification)
    }

    public func matches(_ notification: VisibleNotification) -> Bool {
        if let appEquals, !equals(notification.app, appEquals) {
            return false
        }

        if let appContains, !contains(notification.app, appContains) {
            return false
        }

        if let titleEquals,
        !equals(notification.title, titleEquals) {
            return false
        }

        if let titleContains, !contains(notification.title, titleContains) {
            return false
        }

        if let subtitleEquals,
        !equals(notification.subtitle, subtitleEquals) {
            return false
        }

        if let subtitleContains, !contains(notification.subtitle, subtitleContains) {
            return false
        }

        if let bodyEquals,
        !equals(notification.body, bodyEquals) {
            return false
        }

        if let bodyContains, !contains(notification.body, bodyContains) {
            return false
        }

        if let anyTextContains {
            let searchableText = [
                notification.app,
                notification.title,
                notification.subtitle,
                notification.body
            ].joined(separator: "\n")

            if !contains(searchableText, anyTextContains) {
                return false
            }
        }

        return true
    }

    private func equals(_ value: String, _ expected: String) -> Bool {
        if caseSensitive {
            return value == expected
        }

        return value.lowercased() == expected.lowercased()
    }

    private func contains(_ value: String, _ searchText: String) -> Bool {
        if caseSensitive {
            return value.contains(searchText)
        }

        return value.lowercased().contains(searchText.lowercased())
    }
}

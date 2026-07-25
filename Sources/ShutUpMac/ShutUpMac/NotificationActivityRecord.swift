import Foundation

/// One notification-centric row for the Activity table.
///
/// The table displays one record per notification appearance. Related
/// activity items are retained for the future diagnostics inspector.
nonisolated struct NotificationActivityRecord: Identifiable, Sendable {
    let id: String

    private(set) var notification: ActivityNotificationSnapshot
    private(set) var appearedAt: Date
    private(set) var ruleNames: [String]
    private(set) var activityItems: [ActivityItem]

    init?(from item: ActivityItem) {
        guard item.kind == .notificationAppeared,
              let notification = item.notification else {
            return nil
        }

        self.id = notification.key
        self.notification = notification
        self.appearedAt = item.timestamp
        self.ruleNames = []
        self.activityItems = []

        append(item)
    }

    mutating func append(_ item: ActivityItem) {
        if let notification = item.notification {
            self.notification = notification
        }

        activityItems.append(item)

        if item.kind == .notificationAppeared {
            appearedAt = min(appearedAt, item.timestamp)
        }

        if let ruleName = normalized(item.ruleName),
           !ruleNames.contains(ruleName) {
            ruleNames.append(ruleName)
            ruleNames.sort()
        }
    }

    var app: String {
        notification.app
    }

    var title: String {
        notification.title
    }

    var subtitle: String {
        notification.subtitle
    }

    var body: String {
        notification.body
    }

    var rulesMatchedDisplay: String {
        ruleNames.isEmpty
            ? "—"
            : ruleNames.joined(separator: ", ")
    }

    private func normalized(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }
}

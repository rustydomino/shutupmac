import Foundation

/// One notification-centric row for the Activity table.
///
/// The table displays one record per notification appearance. Related
/// activity items are retained for the future diagnostics inspector.
nonisolated struct NotificationActivityRecord:
    Identifiable,
    Sendable
{
    let id: String

    private(set) var notification:
        ActivityNotificationSnapshot

    private(set) var appearedAt: Date

    private(set) var matchedRules:
        [MatchedRuleSnapshot]

    private(set) var activityItems:
        [ActivityItem]

    init?(from item: ActivityItem) {
        guard item.kind == .notificationAppeared,
              let notification = item.notification else {
            return nil
        }

        self.id = notification.key
        self.notification = notification
        self.appearedAt = item.timestamp
        self.matchedRules = []
        self.activityItems = []

        append(item)
    }

    mutating func append(_ item: ActivityItem) {
        if let notification = item.notification {
            self.notification = notification
        }

        activityItems.append(item)

        if item.kind == .notificationAppeared {
            appearedAt = min(
                appearedAt,
                item.timestamp
            )
        }

        for matchedRule in item.matchedRules {
            let alreadyPresent = matchedRules.contains {
                $0.id == matchedRule.id
            }

            guard !alreadyPresent else {
                continue
            }

            matchedRules.append(matchedRule)
        }

        matchedRules.sort {
            $0.name.localizedCaseInsensitiveCompare(
                $1.name
            ) == .orderedAscending
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

    var matchedRuleCount: Int {
        matchedRules.count
    }

    var rulesMatchedDisplay: String {
        switch matchedRuleCount {
        case 0:
            return "—"

        case 1:
            return "1 rule matched"

        default:
            return "\(matchedRuleCount) rules matched"
        }
    }
}
import Foundation

/// The kind of row displayed in the Activity viewer.
nonisolated enum ActivityItemKind: String, Sendable {
    case notificationAppeared
    case notificationDisappeared
    case notificationDisappearedUnobserved
    case actionRun
    case actionVerification
}

/// A copy of notification data that is safe to pass from the monitoring
/// queue to the main actor.
nonisolated struct ActivityNotificationSnapshot: Sendable {
    let key: String
    let app: String
    let title: String
    let subtitle: String
    let body: String
}

/// An app-owned copy of an action configured on a matched rule.
nonisolated enum MatchedRuleActionSnapshot: Sendable, Equatable {
    case dismissNotification(command: String)

    case runCommand(
        command: String,
        arguments: [String]
    )

    case diagnosticLog(message: String)

    var displayName: String {
        switch self {
        case .dismissNotification:
            return "Dismiss notification"

        case .runCommand:
            return "Run command or script"

        case .diagnosticLog:
            return "Diagnostic log"
        }
    }
}

/// An app-owned copy of a rule reported by NotilogCore.
nonisolated struct MatchedRuleSnapshot:
    Identifiable,
    Sendable,
    Equatable
{
    let id: UUID
    let name: String
    let actions: [MatchedRuleActionSnapshot]
}

/// One row in the Activity viewer.
nonisolated struct ActivityItem: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let kind: ActivityItemKind
    let summary: String
    let detail: String?
    let notification: ActivityNotificationSnapshot?
    let matchedRules: [MatchedRuleSnapshot]
    let ruleName: String?
    let actionRunID: Int64?
    let status: String?

    init(
        id: UUID = UUID(),
        timestamp: Date,
        kind: ActivityItemKind,
        summary: String,
        detail: String? = nil,
        notification: ActivityNotificationSnapshot? = nil,
        matchedRules: [MatchedRuleSnapshot] = [],
        ruleName: String? = nil,
        actionRunID: Int64? = nil,
        status: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.summary = summary
        self.detail = detail
        self.notification = notification
        self.matchedRules = matchedRules
        self.ruleName = ruleName
        self.actionRunID = actionRunID
        self.status = status
    }
}

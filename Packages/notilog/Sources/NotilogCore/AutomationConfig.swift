import Foundation

public struct AutomationConfig: Codable {
    public let rules: [AutomationRuleConfig]

    public init(rules: [AutomationRuleConfig] = []) {
        self.rules = rules
    }

    public static func load(from url: URL) throws -> AutomationConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(AutomationConfig.self, from: data)
    }

    public func notificationRules() throws -> [NotificationRule] {
        try rules.map { try $0.notificationRule() }
    }
}

public struct AutomationRuleConfig: Codable {
    public let id: UUID
    public let name: String
    public let enabled: Bool?
    public let match: NotificationMatchConfig
    public let actions: [NotificationActionConfig]

    public func notificationRule() throws -> NotificationRule {
        NotificationRule(
            id: id,
            name: name,
            enabled: enabled ?? true,
            criteria: match.criteria(),
            actions: try actions.map { try $0.action() }
        )
    }
}

public struct NotificationMatchConfig: Codable {
    public let eventTypes: [NotificationEventType]?

    public let appEquals: String?
    public let appContains: String?

    public let titleContains: String?
    public let subtitleContains: String?
    public let bodyContains: String?

    public let anyTextContains: String?

    public let caseSensitive: Bool?

    public func criteria() -> NotificationMatchCriteria {
        NotificationMatchCriteria(
            eventTypes: eventTypes,
            appEquals: appEquals,
            appContains: appContains,
            titleContains: titleContains,
            subtitleContains: subtitleContains,
            bodyContains: bodyContains,
            anyTextContains: anyTextContains,
            caseSensitive: caseSensitive ?? false
        )
    }
}

public struct NotificationActionConfig: Codable {
    public let type: String
    public let message: String?
    public let command: String?
    public let arguments: [String]?

    public func action() throws -> NotificationAction {
        switch type {
        case "exec":
            guard let command, !command.isEmpty else {
                throw AutomationConfigError.missingExecCommand
            }

            return .exec(
                command: command,
                arguments: arguments ?? []
            )

        case "dryRunLog", "dry_run_log":
            guard let message, !message.isEmpty else {
                throw AutomationConfigError.missingDryRunLogMessage
            }

            return .dryRunLog(message: message)

        case "shutupmac_dismiss":
            return .shutUpMacDismiss(
                command: command ?? NotificationAction.defaultShutUpMacCommand
            )

        default:
            throw AutomationConfigError.unknownActionType(type)
        }
    }
}

public enum AutomationConfigError: Error, Equatable, CustomStringConvertible {
    case unknownActionType(String)
    case missingExecCommand
    case missingDryRunLogMessage

    public var description: String {
        switch self {
        case .unknownActionType(let type):
            return "Unknown action type: \(type)"

        case .missingExecCommand:
            return "Exec action is missing command"

        case .missingDryRunLogMessage:
            return "Dry-run log action is missing message"
        }
    }
}

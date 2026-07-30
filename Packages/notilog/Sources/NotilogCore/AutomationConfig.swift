import Foundation

public struct AutomationConfig:
    Codable,
    @unchecked Sendable
{
    public let rules: [AutomationRuleConfig]

    public init(rules: [AutomationRuleConfig] = []) {
        self.rules = rules
    }

    public func settingRuleEnabled(
        id: UUID,
        enabled: Bool
    ) -> AutomationConfig {
        AutomationConfig(
            rules: rules.map { rule in
                guard rule.id == id else {
                    return rule
                }

                return AutomationRuleConfig(
                    id: rule.id,
                    name: rule.name,
                    enabled: enabled,
                    match: rule.match,
                    exceptions: rule.exceptions,
                    actions: rule.actions
                )
            }
        )
    }

    public func addingRule(
        _ rule: AutomationRuleConfig
    ) -> AutomationConfig {
        AutomationConfig(
            rules: rules + [rule]
        )
    }

    public func replacingRule(
        _ replacement: AutomationRuleConfig
    ) -> AutomationConfig {
        AutomationConfig(
            rules: rules.map { rule in
                rule.id == replacement.id
                    ? replacement
                    : rule
            }
        )
    }

    public func removingRule(
        id: UUID
    ) -> AutomationConfig {
        AutomationConfig(
            rules: rules.filter { rule in
                rule.id != id
            }
        )
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
    public let exceptions: [NotificationExceptionConfig]?
    public let actions: [NotificationActionConfig]

    public init(
        id: UUID,
        name: String,
        enabled: Bool? = nil,
        match: NotificationMatchConfig,
        exceptions: [NotificationExceptionConfig]? = nil,
        actions: [NotificationActionConfig]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.match = match
        self.exceptions = exceptions
        self.actions = actions
    }

    public func notificationRule() throws -> NotificationRule {
        try NotificationRule(
            id: id,
            name: name,
            enabled: enabled ?? true,
            criteria: match.criteria(),
            exceptions: (exceptions ?? []).map {
                $0.exception()
            },
            actions: actions.map { try $0.action() }
        )
    }
}

public struct NotificationMatchConfig: Codable {
    public let eventTypes: [NotificationEventType]?

    public let appEquals: String?
    public let appContains: String?

    public let titleEquals: String?
    public let titleContains: String?

    public let subtitleEquals: String?
    public let subtitleContains: String?

    public let bodyEquals: String?
    public let bodyContains: String?

    public let anyTextContains: String?

    public let caseSensitive: Bool?

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
        caseSensitive: Bool? = nil
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

    public func criteria() -> NotificationMatchCriteria {
        NotificationMatchCriteria(
            eventTypes: eventTypes,
            appEquals: appEquals,
            appContains: appContains,
            titleEquals: titleEquals,
            titleContains: titleContains,
            subtitleEquals: subtitleEquals,
            subtitleContains: subtitleContains,
            bodyEquals: bodyEquals,
            bodyContains: bodyContains,
            anyTextContains: anyTextContains,
            caseSensitive: caseSensitive ?? false
        )
    }
}

public struct NotificationExceptionConfig: Codable {
    public let field: NotificationExceptionField
    public let contains: String

    public init(
        field: NotificationExceptionField,
        contains: String
    ) {
        self.field = field
        self.contains = contains
    }

    public func exception() -> NotificationException {
        NotificationException(
            field: field,
            searchText: contains
        )
    }
}

public struct NotificationActionConfig: Codable {
    public let type: String
    public let message: String?
    public let command: String?
    public let arguments: [String]?

    public init(
        type: String,
        message: String? = nil,
        command: String? = nil,
        arguments: [String]? = nil
    ) {
        self.type = type
        self.message = message
        self.command = command
        self.arguments = arguments
    }

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
        case let .unknownActionType(type):
            return "Unknown action type: \(type)"

        case .missingExecCommand:
            return "Exec action is missing command"

        case .missingDryRunLogMessage:
            return "Dry-run log action is missing message"
        }
    }
}

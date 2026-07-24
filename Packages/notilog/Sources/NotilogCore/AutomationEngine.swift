import Foundation

public struct AutomationMatch {
    public let ruleName: String
    public let action: NotificationAction
    public let event: NotificationEvent

    public init(
        ruleName: String,
        action: NotificationAction,
        event: NotificationEvent
    ) {
        self.ruleName = ruleName
        self.action = action
        self.event = event
    }
}

public final class AutomationEngine {
    private let rules: [NotificationRule]

    public var configuredRules: [NotificationRule] {
            rules
    }

    public init(rules: [NotificationRule]) {
        self.rules = rules
    }

    public func evaluate(_ event: NotificationEvent) -> [AutomationMatch] {
        var matches: [AutomationMatch] = []

        for rule in rules where rule.matches(event) {
            for action in rule.actions {
                matches.append(
                    AutomationMatch(
                        ruleName: rule.name,
                        action: action,
                        event: event
                    )
                )
            }
        }

        return matches
    }

    public static func builtInProbe() -> AutomationEngine {
        AutomationEngine(
            rules: BuiltInAutomationRules.probeRules()
        )
    }
    
    public static func dryRunProbe() -> AutomationEngine {
        builtInProbe()
    }

}

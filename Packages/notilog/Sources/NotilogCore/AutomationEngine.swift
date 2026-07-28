import Foundation

public struct MatchedAutomationRule {
    public let ruleID: UUID
    public let ruleName: String
    public let actions: [NotificationAction]
    public let event: NotificationEvent

    public init(
        ruleID: UUID,
        ruleName: String,
        actions: [NotificationAction],
        event: NotificationEvent
    ) {
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.actions = actions
        self.event = event
    }
}

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

public final class AutomationEngine:
    @unchecked Sendable {
    private let rules: [NotificationRule]

    public var configuredRules: [NotificationRule] {
            rules
    }

    public init(rules: [NotificationRule]) {
        self.rules = rules
    }

public func evaluateRules(
    _ event: NotificationEvent
) -> [MatchedAutomationRule] {
    rules.compactMap { rule in
        guard rule.matches(event) else {
            return nil
        }

        return MatchedAutomationRule(
            ruleID: rule.id,
            ruleName: rule.name,
            actions: rule.actions,
            event: event
        )
    }
}

public func evaluate(
    _ event: NotificationEvent
) -> [AutomationMatch] {
    evaluateRules(event).flatMap { matchedRule in
        matchedRule.actions.map { action in
            AutomationMatch(
                ruleName: matchedRule.ruleName,
                action: action,
                event: matchedRule.event
            )
        }
    }
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

import Foundation

public enum AutomationExecutionMode: Equatable {
    case disabled
    case dryRun
    case runActions
}

public struct NotificationAutomationProcessingResult {
    public let matchedRules: [MatchedAutomationRule]
    public let actionResults: [ActionRunResult]

    public init(
        matchedRules: [MatchedAutomationRule],
        actionResults: [ActionRunResult]
    ) {
        self.matchedRules = matchedRules
        self.actionResults = actionResults
    }
}

public final class NotificationAutomationProcessor {
    private let engine: AutomationEngine
    private let runner: ActionRunner

    public init(
        engine: AutomationEngine,
        runner: ActionRunner = ActionRunner()
    ) {
        self.engine = engine
        self.runner = runner
    }

    public func process(
        event: NotificationEvent,
        mode: AutomationExecutionMode
    ) -> [ActionRunResult] {
        processDetailed(
            event: event,
            mode: mode
        ).actionResults
    }

    public func processDetailed(
        event: NotificationEvent,
        mode: AutomationExecutionMode
    ) -> NotificationAutomationProcessingResult {
        let matchedRules = engine.evaluateRules(event)

        guard mode != .disabled else {
            return NotificationAutomationProcessingResult(
                matchedRules: matchedRules,
                actionResults: []
            )
        }

        let actionResults = matchedRules.flatMap { matchedRule in
            matchedRule.actions.map { action in
                let match = AutomationMatch(
                    ruleName: matchedRule.ruleName,
                    action: action,
                    event: matchedRule.event
                )

                switch mode {
                case .disabled:
                    preconditionFailure(
                        "Disabled automation was handled before execution"
                    )

                case .dryRun:
                    return runner.runDryRun(match)

                case .runActions:
                    return runner.run(match)
                }
            }
        }

        return NotificationAutomationProcessingResult(
            matchedRules: matchedRules,
            actionResults: actionResults
        )
    }

}

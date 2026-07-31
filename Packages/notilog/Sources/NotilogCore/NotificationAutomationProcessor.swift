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
    private var engine: AutomationEngine
    private let runner: ActionRunner

    public init(
        engine: AutomationEngine,
        runner: ActionRunner = ActionRunner()
    ) {
        self.engine = engine
        self.runner = runner
    }

    public func replaceEngine(
        _ engine: AutomationEngine
    ) {
        self.engine = engine
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

    public func replaceConfiguration(
        _ configuration: AutomationConfig
    ) throws {
        let candidateEngine = AutomationEngine(
            rules: try configuration.notificationRules()
        )

        replaceEngine(candidateEngine)
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

        var actionResults: [ActionRunResult] = []
        var hasProcessedDismissAction = false

        for matchedRule in matchedRules {
            for action in matchedRule.actions {
                if case .shutUpMacDismiss = action {
                    guard !hasProcessedDismissAction else {
                        continue
                    }

                    hasProcessedDismissAction = true
                }

                let match = AutomationMatch(
                    ruleName: matchedRule.ruleName,
                    action: action,
                    event: matchedRule.event
                )

                let result: ActionRunResult

                switch mode {
                case .disabled:
                    preconditionFailure(
                        "Disabled automation was handled before execution"
                    )

                case .dryRun:
                    result = runner.runDryRun(match)

                case .runActions:
                    result = runner.run(match)
                }

                actionResults.append(result)
            }
        }

        return NotificationAutomationProcessingResult(
            matchedRules: matchedRules,
            actionResults: actionResults
        )
    }

}

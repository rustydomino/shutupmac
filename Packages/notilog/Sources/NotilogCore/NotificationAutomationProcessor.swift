import Foundation

public enum AutomationExecutionMode: Equatable {
    case disabled
    case dryRun
    case runActions
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
        guard mode != .disabled else {
            return []
        }

        let matches = engine.evaluate(event)

        return matches.map { match in
            switch mode {
            case .disabled:
                preconditionFailure(
                    "Disabled automation was handled before evaluation"
                )

            case .dryRun:
                runner.runDryRun(match)

            case .runActions:
                runner.run(match)
            }
        }
    }
}
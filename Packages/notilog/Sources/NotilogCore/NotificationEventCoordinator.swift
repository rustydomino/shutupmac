import Foundation

public struct CoordinatedNotificationEvent {
    public let event: NotificationEvent
    public let matchedRules: [MatchedAutomationRule]
    public let actionResults: [CoordinatedActionResult]

    public init(
        event: NotificationEvent,
        matchedRules: [MatchedAutomationRule],
        actionResults: [CoordinatedActionResult]
    ) {
        self.event = event
        self.matchedRules = matchedRules
        self.actionResults = actionResults
    }
}

public final class NotificationEventCoordinator {
    private let persistenceCoordinator:
        NotificationEventPersistenceCoordinator

    private let automationProcessor:
        NotificationAutomationProcessor

    private let actionResultCoordinator:
        ActionResultCoordinator

    public init(
        persistenceCoordinator:
            NotificationEventPersistenceCoordinator,
        automationProcessor:
            NotificationAutomationProcessor,
        actionResultCoordinator:
            ActionResultCoordinator
    ) {
        self.persistenceCoordinator = persistenceCoordinator
        self.automationProcessor = automationProcessor
        self.actionResultCoordinator = actionResultCoordinator
    }

    public func process(
        _ events: [NotificationEvent],
        automationMode: AutomationExecutionMode,
        actionTimestampProvider: () -> Date,
        beforeAutomation: (NotificationEvent) -> Void,
        beforeActionResultCoordination: (ActionRunResult) -> Void
    ) throws -> [CoordinatedNotificationEvent] {
        try persistenceCoordinator.persist(events)

        return try events.map { event in
            beforeAutomation(event)

            let automationResult =
            automationProcessor.processDetailed(
                event: event,
                mode: automationMode
            )

            var coordinatedActionResults:
                [CoordinatedActionResult] = []

            for actionResult in automationResult.actionResults {
                beforeActionResultCoordination(actionResult)

                let coordinatedResults =
                    try actionResultCoordinator.process(
                        [actionResult],
                        at: actionTimestampProvider()
                    )

                coordinatedActionResults.append(
                    contentsOf: coordinatedResults
                )
            }

            return CoordinatedNotificationEvent(
                event: event,
                matchedRules: automationResult.matchedRules,
                actionResults: coordinatedActionResults
            )
        }
    }
}

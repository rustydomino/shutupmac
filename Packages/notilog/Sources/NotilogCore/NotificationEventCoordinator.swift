import Foundation

public struct CoordinatedNotificationEvent {
    public let event: NotificationEvent
    public let actionResults: [CoordinatedActionResult]

    public init(
        event: NotificationEvent,
        actionResults: [CoordinatedActionResult]
    ) {
        self.event = event
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

            let actionResults = automationProcessor.process(
                event: event,
                mode: automationMode
            )

            var coordinatedActionResults:
                [CoordinatedActionResult] = []

            for actionResult in actionResults {
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
                actionResults: coordinatedActionResults
            )
        }
    }
}
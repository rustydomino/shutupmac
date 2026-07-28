import Foundation

public struct CoordinatedActionResult {
    public let result: ActionRunResult
    public let actionRunID: Int64?

    public init(
        result: ActionRunResult,
        actionRunID: Int64?
    ) {
        self.result = result
        self.actionRunID = actionRunID
    }
}

public final class ActionResultCoordinator {
    private var store: NotificationStore?
    private var session: ObservationSession
    private var redactionPolicy: RedactionPolicy
    private let cycleProcessor: MonitoringCycleProcessor
    private let dismissalVerificationDelay: TimeInterval

    public init(
        store: NotificationStore?,
        session: ObservationSession,
        redactionPolicy: RedactionPolicy,
        cycleProcessor: MonitoringCycleProcessor,
        dismissalVerificationDelay: TimeInterval
    ) {
        self.store = store
        self.session = session
        self.redactionPolicy = redactionPolicy
        self.cycleProcessor = cycleProcessor
        self.dismissalVerificationDelay = dismissalVerificationDelay
    }

    public func replacePersistence(
        store: NotificationStore?,
        session: ObservationSession
    ) {
        self.store = store
        self.session = session
    }

    public func replaceRedactionPolicy(
        _ policy: RedactionPolicy
    ) {
        redactionPolicy = policy
    }

    public func process(
        _ results: [ActionRunResult],
        at timestamp: Date
    ) throws -> [CoordinatedActionResult] {
        try results.map { result in
            let actionRunID: Int64?

            if let store {
                let storedResult = redactionPolicy.applying(
                    to: result
                )

                actionRunID = try store.insert(
                    storedResult,
                    session: session
                )
            } else {
                actionRunID = nil
            }

            if result.verificationStatus == .pending {
                cycleProcessor.scheduleActionVerification(
                    actionRunID: actionRunID,
                    notificationKey: result.event.notification.key,
                    requestedAt: timestamp,
                    delay: dismissalVerificationDelay
                )
            }

            return CoordinatedActionResult(
                result: result,
                actionRunID: actionRunID
            )
        }
    }
}

import Foundation

public struct PendingActionVerification: Equatable {
    public let actionRunID: Int64?
    public let notificationKey: String
    public let verifyAfter: Date

    public init(
        actionRunID: Int64?,
        notificationKey: String,
        verifyAfter: Date
    ) {
        self.actionRunID = actionRunID
        self.notificationKey = notificationKey
        self.verifyAfter = verifyAfter
    }
}

public struct CompletedActionVerification: Equatable {
    public let actionRunID: Int64?
    public let notificationKey: String
    public let status: ActionVerificationStatus

    public init(
        actionRunID: Int64?,
        notificationKey: String,
        status: ActionVerificationStatus
    ) {
        self.actionRunID = actionRunID
        self.notificationKey = notificationKey
        self.status = status
    }
}

public final class ActionVerificationProcessor {
    private var pendingVerifications: [PendingActionVerification]

    public init(
        pendingVerifications: [PendingActionVerification] = []
    ) {
        self.pendingVerifications = pendingVerifications
    }

    public func schedule(
        actionRunID: Int64?,
        notificationKey: String,
        requestedAt timestamp: Date,
        delay: TimeInterval
    ) {
        pendingVerifications.append(
            PendingActionVerification(
                actionRunID: actionRunID,
                notificationKey: notificationKey,
                verifyAfter: timestamp.addingTimeInterval(delay)
            )
        )
    }

    public func processDue(
        visibleNotifications: [VisibleNotification],
        at timestamp: Date
    ) -> [CompletedActionVerification] {
        var remainingVerifications: [PendingActionVerification] = []
        var completedVerifications: [CompletedActionVerification] = []

        for verification in pendingVerifications {
            guard verification.verifyAfter <= timestamp else {
                remainingVerifications.append(verification)
                continue
            }

            let status = ActionVerificationEvaluator.evaluate(
                notificationKey: verification.notificationKey,
                visibleNotifications: visibleNotifications
            )

            completedVerifications.append(
                CompletedActionVerification(
                    actionRunID: verification.actionRunID,
                    notificationKey: verification.notificationKey,
                    status: status
                )
            )
        }

        pendingVerifications = remainingVerifications

        return completedVerifications
    }
}
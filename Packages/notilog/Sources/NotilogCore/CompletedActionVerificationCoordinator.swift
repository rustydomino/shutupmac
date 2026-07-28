public final class CompletedActionVerificationCoordinator {
    private var store: NotificationStore?

    public init(
        store: NotificationStore?
    ) {
        self.store = store
    }

    public func replaceStore(
        _ store: NotificationStore?
    ) {
        self.store = store
    }

    public func process(
        _ completedVerifications: [CompletedActionVerification]
    ) throws -> [CompletedActionVerification] {
        for verification in completedVerifications {
            guard
                let store,
                let actionRunID = verification.actionRunID
            else {
                continue
            }

            try store.updateActionVerificationStatus(
                verification.status,
                forActionRunID: actionRunID
            )
        }

        return completedVerifications
    }
}

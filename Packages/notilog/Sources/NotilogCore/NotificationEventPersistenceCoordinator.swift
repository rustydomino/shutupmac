public final class NotificationEventPersistenceCoordinator {
    private let store: NotificationStore?
    private let session: ObservationSession
    private let redactionPolicy: RedactionPolicy

    public init(
        store: NotificationStore?,
        session: ObservationSession,
        redactionPolicy: RedactionPolicy
    ) {
        self.store = store
        self.session = session
        self.redactionPolicy = redactionPolicy
    }

    public func persist(
        _ events: [NotificationEvent]
    ) throws {
        guard let store else {
            return
        }

        let storedEvents = events.map {
            redactionPolicy.applying(to: $0)
        }

        try store.insert(
            storedEvents,
            session: session
        )
    }
}
public final class NotificationEventPersistenceCoordinator {
    private var store: NotificationStore?
    private var session: ObservationSession
    private var redactionPolicy: RedactionPolicy

    public init(
        store: NotificationStore?,
        session: ObservationSession,
        redactionPolicy: RedactionPolicy
    ) {
        self.store = store
        self.session = session
        self.redactionPolicy = redactionPolicy
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

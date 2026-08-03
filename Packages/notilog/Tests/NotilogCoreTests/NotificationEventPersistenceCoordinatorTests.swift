import Foundation
@testable import NotilogCore
import XCTest

final class NotificationEventPersistenceCoordinatorTests: XCTestCase {
    func testNoLoggingAcceptsEventsWithoutPersistence() throws {
        let coordinator = NotificationEventPersistenceCoordinator(
            store: nil,
            session: testSession(),
            redactionPolicy: .disabled
        )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-A",
                    title: "Test notification"
                )
            ]
        )
    }

    func testLoggingPersistsEventsWithSessionID() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = testSession()

        let coordinator = NotificationEventPersistenceCoordinator(
            store: store,
            session: session,
            redactionPolicy: .disabled
        )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-A",
                    title: "First notification"
                )
            ]
        )

        let records = try store.recentEvents(limit: 10)
        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.sessionID, session.id)
        XCTAssertEqual(record.event.type, .appeared)
        XCTAssertEqual(
            record.event.notification.key,
            "alert-A"
        )
        XCTAssertEqual(
            record.event.notification.title,
            "First notification"
        )
    }

    func testRedactionAppliesToStorageButNotOriginalEvent() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = NotificationEventPersistenceCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: RedactionPolicy(
                fields: [.title, .body]
            )
        )

        let originalEvent = sampleEvent(
            key: "alert-A",
            title: "Secret title",
            body: "Secret body"
        )

        try coordinator.persist([originalEvent])

        XCTAssertEqual(
            originalEvent.notification.title,
            "Secret title"
        )
        XCTAssertEqual(
            originalEvent.notification.body,
            "Secret body"
        )

        let records = try store.recentEvents(limit: 10)
        let storedEvent = try XCTUnwrap(records.first).event

        XCTAssertEqual(
            storedEvent.notification.title,
            "[REDACTED]"
        )
        XCTAssertEqual(
            storedEvent.notification.body,
            "[REDACTED]"
        )
        XCTAssertEqual(
            storedEvent.notification.key,
            "alert-A"
        )
    }

    func testReplacingRedactionPolicyAffectsOnlySubsequentWrites() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = NotificationEventPersistenceCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: .disabled
        )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-A",
                    title: "First secret title",
                    body: "First secret body"
                )
            ]
        )

        coordinator.replaceRedactionPolicy(
            RedactionPolicy(
                fields: [.title, .body]
            )
        )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-B",
                    title: "Second secret title",
                    body: "Second secret body"
                )
            ]
        )

        coordinator.replaceRedactionPolicy(.disabled)

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-C",
                    title: "Third secret title",
                    body: "Third secret body"
                )
            ]
        )

        let storedEvents = try store.recentEvents(limit: 10)
            .map(\.event)

        XCTAssertEqual(storedEvents.count, 3)

        let firstEvent = try XCTUnwrap(
            storedEvents.first {
                $0.notification.key == "alert-A"
            }
        )

        let secondEvent = try XCTUnwrap(
            storedEvents.first {
                $0.notification.key == "alert-B"
            }
        )

        let thirdEvent = try XCTUnwrap(
            storedEvents.first {
                $0.notification.key == "alert-C"
            }
        )

        XCTAssertEqual(
            firstEvent.notification.title,
            "First secret title"
        )
        XCTAssertEqual(
            firstEvent.notification.body,
            "First secret body"
        )

        XCTAssertEqual(
            secondEvent.notification.title,
            "[REDACTED]"
        )
        XCTAssertEqual(
            secondEvent.notification.body,
            "[REDACTED]"
        )
        XCTAssertEqual(
            secondEvent.notification.app,
            "Notigen"
        )

        XCTAssertEqual(
            thirdEvent.notification.title,
            "Third secret title"
        )
        XCTAssertEqual(
            thirdEvent.notification.body,
            "Third secret body"
        )
    }

    func testMixedUnredactedRedactedAndTruncatedEventsRemainQueryable()
        throws
    {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator =
            NotificationEventPersistenceCoordinator(
                store: store,
                session: testSession(),
                redactionPolicy: .disabled
            )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-unredacted",
                    title: "Visible title",
                    body: "Visible body",
                    timestamp:
                        Date(timeIntervalSince1970: 10)
                )
            ]
        )

        coordinator.replaceRedactionPolicy(
            RedactionPolicy(
                fields: [
                    .title,
                    .body,
                ]
            )
        )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-redacted",
                    title: "Secret title",
                    body: "Secret body",
                    timestamp:
                        Date(timeIntervalSince1970: 20)
                )
            ]
        )

        coordinator.replaceRedactionPolicy(
            .disabled
        )

        let longTitle =
            String(
                repeating: "T",
                count: 5_000
            )

        let longBody =
            String(
                repeating: "B",
                count: 5_000
            )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-truncated",
                    title: longTitle,
                    body: longBody,
                    timestamp:
                        Date(timeIntervalSince1970: 30)
                )
            ]
        )

        let records =
            try store.recentEvents(limit: 10)

        XCTAssertEqual(
            records.map {
                $0.event.notification.key
            },
            [
                "alert-unredacted",
                "alert-redacted",
                "alert-truncated",
            ]
        )

        let unredacted =
            records[0].event.notification

        XCTAssertEqual(
            unredacted.title,
            "Visible title"
        )

        XCTAssertEqual(
            unredacted.body,
            "Visible body"
        )

        let redacted =
            records[1].event.notification

        XCTAssertEqual(
            redacted.title,
            "[REDACTED]"
        )

        XCTAssertEqual(
            redacted.body,
            "[REDACTED]"
        )

        let truncated =
            records[2].event.notification

        XCTAssertEqual(
            truncated.title.count,
            4_096
        )

        XCTAssertEqual(
            truncated.body.count,
            4_096
        )

        XCTAssertEqual(
            truncated.title,
            String(longTitle.prefix(4_096))
        )

        XCTAssertEqual(
            truncated.body,
            String(longBody.prefix(4_096))
        )
    }

    func testEmptyBatchDoesNotInsertRecords() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = NotificationEventPersistenceCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: .disabled
        )

        try coordinator.persist([])

        let records = try store.recentEvents(limit: 10)

        XCTAssertTrue(records.isEmpty)
    }

    func testEventsPreserveInputOrder() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = NotificationEventPersistenceCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: .disabled
        )

        try coordinator.persist(
            [
                sampleEvent(
                    key: "alert-A",
                    title: "First notification",
                    timestamp: Date(timeIntervalSince1970: 10)
                ),
                sampleEvent(
                    key: "alert-B",
                    title: "Second notification",
                    timestamp: Date(timeIntervalSince1970: 20)
                ),
                sampleEvent(
                    key: "alert-C",
                    title: "Third notification",
                    timestamp: Date(timeIntervalSince1970: 30)
                )
            ]
        )

        let records = try store.recentEvents(limit: 10)

        XCTAssertEqual(
            records.map { $0.event.notification.key },
            ["alert-A", "alert-B", "alert-C"]
        )

        XCTAssertEqual(
            records.map { $0.event.notification.title },
            [
                "First notification",
                "Second notification",
                "Third notification"
            ]
        )
    }

    private func sampleEvent(
        type: NotificationEventType = .appeared,
        key: String,
        title: String,
        body: String = "Test body",
        timestamp: Date = Date(timeIntervalSince1970: 10)
    ) -> NotificationEvent {
        NotificationEvent(
            type: type,
            notification: VisibleNotification(
                key: key,
                app: "Notigen",
                title: title,
                subtitle: "",
                body: body
            ),
            timestamp: timestamp
        )
    }

    private func testSession() -> ObservationSession {
        ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString).sqlite"
            )
    }
}

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
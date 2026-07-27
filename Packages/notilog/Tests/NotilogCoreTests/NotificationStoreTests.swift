import Foundation
@testable import NotilogCore
import XCTest

final class NotificationStoreTests: XCTestCase {
    func testActionVerificationStatusRoundTripsThroughSQLite() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notilog-\(UUID().uuidString).sqlite")

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(path: databaseURL.path)
        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let notification = VisibleNotification(
            key: "AXNotificationCenterAlert|ABC-123",
            app: "Notigen",
            title: "Test notification",
            subtitle: "",
            body: "Testing ShutUpMac verification."
        )

        let event = NotificationEvent(
            type: .appeared,
            notification: notification,
            timestamp: Date(timeIntervalSince1970: 2)
        )

        let result = ActionRunResult(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: "/usr/bin/true"
            ),
            resolvedAction: .shutUpMacDismiss(
                command: "/usr/bin/true",
                notificationKey: notification.key
            ),
            event: event,
            status: .succeeded,
            message: "ShutUpMac accepted dismissal request",
            exitCode: 0,
            verificationStatus: .pending
        )

        let actionRunID = try store.insert(
            result,
            session: session
        )

        let records = try store.recentActionRuns(limit: 10)

        XCTAssertEqual(records.count, 1)

        let record = try XCTUnwrap(records.first)

        XCTAssertGreaterThan(actionRunID, 0)
        XCTAssertEqual(record.id, actionRunID)
        XCTAssertEqual(record.status, .succeeded)

        XCTAssertEqual(record.verificationStatus, .pending)
        XCTAssertEqual(record.message, "ShutUpMac accepted dismissal request")
        XCTAssertEqual(record.exitCode, 0)
        XCTAssertEqual(
            record.notification.key,
            "AXNotificationCenterAlert|ABC-123"
        )

        try store.updateActionVerificationStatus(
            .probablySucceeded,
            forActionRunID: actionRunID
        )

        let updatedRecords = try store.recentActionRuns(limit: 10)
        let updatedRecord = try XCTUnwrap(updatedRecords.first)

        XCTAssertEqual(updatedRecord.id, actionRunID)
        XCTAssertEqual(
            updatedRecord.verificationStatus,
            .probablySucceeded
        )
    }

    func testRecentAppearanceEventsReturnsNewestAppearancesOldestFirst() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString).sqlite"
            )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let firstNotification = VisibleNotification(
            key: "notification-1",
            app: "Mail",
            title: "First",
            subtitle: "",
            body: "First notification"
        )

        let secondNotification = VisibleNotification(
            key: "notification-2",
            app: "Messages",
            title: "Second",
            subtitle: "",
            body: "Second notification"
        )

        let thirdNotification = VisibleNotification(
            key: "notification-3",
            app: "Calendar",
            title: "Third",
            subtitle: "",
            body: "Third notification"
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: firstNotification,
                timestamp: Date(timeIntervalSince1970: 10)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .disappeared,
                notification: firstNotification,
                timestamp: Date(timeIntervalSince1970: 20)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: secondNotification,
                timestamp: Date(timeIntervalSince1970: 30)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .disappeared,
                notification: secondNotification,
                timestamp: Date(timeIntervalSince1970: 40)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: thirdNotification,
                timestamp: Date(timeIntervalSince1970: 50)
            ),
            session: session
        )

        let records = try store.recentAppearanceEvents(
            limit: 2
        )

        XCTAssertEqual(records.count, 2)

        XCTAssertEqual(
            records.map(\.event.notification.key),
            [
                "notification-2",
                "notification-3"
            ]
        )

        XCTAssertTrue(
            records.allSatisfy {
                $0.event.type == .appeared
            }
        )
    }

    func testRecentAppearanceEventsCapsResultAtOneThousand() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString).sqlite"
            )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        for index in 1...1_001 {
            let notification = VisibleNotification(
                key: "notification-\(index)",
                app: "Test App",
                title: "Notification \(index)",
                subtitle: "",
                body: "Body \(index)"
            )

            try store.insert(
                NotificationEvent(
                    type: .appeared,
                    notification: notification,
                    timestamp: Date(
                        timeIntervalSince1970:
                            TimeInterval(index)
                    )
                ),
                session: session
            )
        }

        let records = try store.recentAppearanceEvents(
            limit: 50_000
        )

        XCTAssertEqual(records.count, 1_000)

        XCTAssertEqual(
            records.first?.event.notification.key,
            "notification-2"
        )

        XCTAssertEqual(
            records.last?.event.notification.key,
            "notification-1001"
        )
    }

}

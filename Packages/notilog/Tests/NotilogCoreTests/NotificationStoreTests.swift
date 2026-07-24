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
}

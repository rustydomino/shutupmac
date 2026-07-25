import Foundation
@testable import NotilogCore
import XCTest

final class CompletedActionVerificationCoordinatorTests:
    XCTestCase
{
    func testNoLoggingReturnsVerificationsUnchanged()
        throws
    {
        let coordinator =
            CompletedActionVerificationCoordinator(
                store: nil
            )

        let verifications = [
            CompletedActionVerification(
                actionRunID: nil,
                notificationKey: "alert-A",
                status: .probablySucceeded
            ),
            CompletedActionVerification(
                actionRunID: 42,
                notificationKey: "alert-B",
                status: .definitelyFailed
            )
        ]

        let results = try coordinator.process(
            verifications
        )

        XCTAssertEqual(results, verifications)
    }

    func testLoggedVerificationUpdatesStoredActionRun()
        throws
    {
        let temporaryDirectory =
            try makeTemporaryDirectory()

        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let store = try NotificationStore(
            path: temporaryDirectory
                .appendingPathComponent("notilog.sqlite")
                .path
        )

        let actionRunID = try store.insert(
            sampleActionResult(
                notificationKey: "alert-A"
            ),
            session: testSession()
        )

        let coordinator =
            CompletedActionVerificationCoordinator(
                store: store
            )

        let verification =
            CompletedActionVerification(
                actionRunID: actionRunID,
                notificationKey: "alert-A",
                status: .probablySucceeded
            )

        let results = try coordinator.process(
            [verification]
        )

        XCTAssertEqual(results, [verification])

        let records = try store.recentActionRuns(
            limit: 10
        )

        let record = try XCTUnwrap(records.first)

        XCTAssertEqual(record.id, actionRunID)
        XCTAssertEqual(
            record.verificationStatus,
            .probablySucceeded
        )
    }

    func testMultipleUpdatesPreserveInputOrder()
        throws
    {
        let temporaryDirectory =
            try makeTemporaryDirectory()

        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let store = try NotificationStore(
            path: temporaryDirectory
                .appendingPathComponent("notilog.sqlite")
                .path
        )

        let session = testSession()

        let firstActionRunID = try store.insert(
            sampleActionResult(
                ruleName: "First rule",
                notificationKey: "alert-A"
            ),
            session: session
        )

        let secondActionRunID = try store.insert(
            sampleActionResult(
                ruleName: "Second rule",
                notificationKey: "alert-B"
            ),
            session: session
        )

        let coordinator =
            CompletedActionVerificationCoordinator(
                store: store
            )

        let verifications = [
            CompletedActionVerification(
                actionRunID: secondActionRunID,
                notificationKey: "alert-B",
                status: .definitelyFailed
            ),
            CompletedActionVerification(
                actionRunID: firstActionRunID,
                notificationKey: "alert-A",
                status: .probablySucceeded
            )
        ]

        let results = try coordinator.process(
            verifications
        )

        XCTAssertEqual(results, verifications)

        let records = try store.recentActionRuns(
            limit: 10
        )

        XCTAssertEqual(records.count, 2)

        XCTAssertEqual(
            records[0].verificationStatus,
            .probablySucceeded
        )

        XCTAssertEqual(
            records[1].verificationStatus,
            .definitelyFailed
        )
    }

    func testNilActionRunIDDoesNotUpdateStoredRecords()
        throws
    {
        let temporaryDirectory =
            try makeTemporaryDirectory()

        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let store = try NotificationStore(
            path: temporaryDirectory
                .appendingPathComponent("notilog.sqlite")
                .path
        )

        _ = try store.insert(
            sampleActionResult(
                notificationKey: "alert-A"
            ),
            session: testSession()
        )

        let coordinator =
            CompletedActionVerificationCoordinator(
                store: store
            )

        let verification =
            CompletedActionVerification(
                actionRunID: nil,
                notificationKey: "alert-A",
                status: .probablySucceeded
            )

        let results = try coordinator.process(
            [verification]
        )

        XCTAssertEqual(results, [verification])

        let records = try store.recentActionRuns(
            limit: 10
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(
            records[0].verificationStatus,
            .pending
        )
    }

    private func sampleActionResult(
        ruleName: String = "Dismiss notification",
        notificationKey: String
    ) -> ActionRunResult {
        let event = NotificationEvent(
            type: .appeared,
            notification: VisibleNotification(
                key: notificationKey,
                app: "Notigen",
                title: "Test notification",
                subtitle: "",
                body: "Test body"
            ),
            timestamp: Date(
                timeIntervalSince1970: 5
            )
        )

        return ActionRunResult(
            ruleName: ruleName,
            action: .shutUpMacDismiss(
                command: "/usr/bin/true"
            ),
            resolvedAction: .shutUpMacDismiss(
                command: "/usr/bin/true",
                notificationKey: notificationKey
            ),
            event: event,
            status: .succeeded,
            message: "Dismissal request accepted",
            exitCode: 0,
            verificationStatus: .pending
        )
    }

    private func testSession()
        -> ObservationSession
    {
        ObservationSession(
            id: "test-session",
            startedAt: Date(
                timeIntervalSince1970: 1
            )
        )
    }

    private func makeTemporaryDirectory()
        throws -> URL
    {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }
}
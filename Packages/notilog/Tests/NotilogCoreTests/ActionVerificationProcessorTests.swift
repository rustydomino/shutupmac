import Foundation
@testable import NotilogCore
import XCTest

final class ActionVerificationProcessorTests: XCTestCase {
    func testScheduledVerificationWaitsUntilDueTime() {
        let processor = ActionVerificationProcessor()
        let requestedAt = Date(timeIntervalSince1970: 10)

        processor.schedule(
            actionRunID: 42,
            notificationKey: "alert-A",
            requestedAt: requestedAt,
            delay: 2
        )

        let earlyResults = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 11)
        )

        XCTAssertTrue(earlyResults.isEmpty)

        let dueResults = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(
            dueResults,
            [
                CompletedActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-A",
                    status: .probablySucceeded
                )
            ]
        )
    }

    func testDueVerificationDefinitelyFailsWhenNotificationRemainsVisible() {
        let notification = sampleNotification(key: "alert-A")

        let processor = ActionVerificationProcessor(
            pendingVerifications: [
                PendingActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-A",
                    verifyAfter: Date(timeIntervalSince1970: 10)
                )
            ]
        )

        let results = processor.processDue(
            visibleNotifications: [notification],
            at: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(
            results,
            [
                CompletedActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-A",
                    status: .definitelyFailed
                )
            ]
        )
    }

    func testDueVerificationProbablySucceedsWhenNotificationIsGone() {
        let processor = ActionVerificationProcessor(
            pendingVerifications: [
                PendingActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-A",
                    verifyAfter: Date(timeIntervalSince1970: 10)
                )
            ]
        )

        let results = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .probablySucceeded)
    }

    func testNilActionRunIDIsPreservedForNoLoggingMode() {
        let processor = ActionVerificationProcessor()

        processor.schedule(
            actionRunID: nil,
            notificationKey: "alert-A",
            requestedAt: Date(timeIntervalSince1970: 10),
            delay: 2
        )

        let results = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results[0].actionRunID)
        XCTAssertEqual(results[0].notificationKey, "alert-A")
        XCTAssertEqual(results[0].status, .probablySucceeded)
    }

    func testFutureVerificationRemainsPendingAfterDueVerificationCompletes() {
        let processor = ActionVerificationProcessor(
            pendingVerifications: [
                PendingActionVerification(
                    actionRunID: 1,
                    notificationKey: "alert-A",
                    verifyAfter: Date(timeIntervalSince1970: 10)
                ),
                PendingActionVerification(
                    actionRunID: 2,
                    notificationKey: "alert-B",
                    verifyAfter: Date(timeIntervalSince1970: 20)
                )
            ]
        )

        let firstResults = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(firstResults.count, 1)
        XCTAssertEqual(firstResults[0].notificationKey, "alert-A")

        let secondResults = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(secondResults.count, 1)
        XCTAssertEqual(secondResults[0].notificationKey, "alert-B")
    }

    func testCompletedVerificationsPreserveSchedulingOrder() {
        let processor = ActionVerificationProcessor()

        processor.schedule(
            actionRunID: 1,
            notificationKey: "alert-A",
            requestedAt: Date(timeIntervalSince1970: 10),
            delay: 2
        )

        processor.schedule(
            actionRunID: 2,
            notificationKey: "alert-B",
            requestedAt: Date(timeIntervalSince1970: 10),
            delay: 2
        )

        let results = processor.processDue(
            visibleNotifications: [],
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(
            results.map(\.notificationKey),
            ["alert-A", "alert-B"]
        )
    }

    private func sampleNotification(
        key: String
    ) -> VisibleNotification {
        VisibleNotification(
            key: key,
            app: "Notigen",
            title: "Test notification",
            subtitle: "",
            body: "Test body"
        )
    }
}
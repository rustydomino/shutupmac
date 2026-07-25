import Foundation
@testable import NotilogCore
import XCTest

final class MonitoringCycleProcessorTests: XCTestCase {
    func testProcessScanReturnsVerificationRecoveryAndCurrentEvents() {
        let previousNotification = sampleNotification(
            key: "alert-previous"
        )

        let currentNotification = sampleNotification(
            key: "alert-current"
        )

        let processor = MonitoringCycleProcessor(
            previouslyActive: [previousNotification],
            pendingActionVerifications: [
                PendingActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-dismissed",
                    verifyAfter: Date(timeIntervalSince1970: 10)
                )
            ]
        )

        let timestamp = Date(timeIntervalSince1970: 10)

        let result = processor.processScan(
            notifications: [currentNotification],
            at: timestamp
        )

        XCTAssertEqual(
            result.completedActionVerifications,
            [
                CompletedActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-dismissed",
                    status: .probablySucceeded
                )
            ]
        )

        XCTAssertEqual(result.recoveredEvents.count, 1)
        XCTAssertEqual(
            result.recoveredEvents[0].type,
            .disappearedUnobserved
        )
        XCTAssertEqual(
            result.recoveredEvents[0].notification.key,
            "alert-previous"
        )
        XCTAssertEqual(
            result.recoveredEvents[0].timestamp,
            timestamp
        )

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].type, .appeared)
        XCTAssertEqual(
            result.events[0].notification.key,
            "alert-current"
        )
        XCTAssertEqual(result.events[0].timestamp, timestamp)
    }

    func testScheduledVerificationWaitsUntilDueCycle() {
        let processor = MonitoringCycleProcessor()

        processor.scheduleActionVerification(
            actionRunID: nil,
            notificationKey: "alert-A",
            requestedAt: Date(timeIntervalSince1970: 10),
            delay: 2
        )

        let earlyResult = processor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 11)
        )

        XCTAssertTrue(
            earlyResult.completedActionVerifications.isEmpty
        )

        let dueResult = processor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(
            dueResult.completedActionVerifications,
            [
                CompletedActionVerification(
                    actionRunID: nil,
                    notificationKey: "alert-A",
                    status: .probablySucceeded
                )
            ]
        )
    }

    func testDueVerificationFailsWhenNotificationRemainsVisible() {
        let notification = sampleNotification(key: "alert-A")

        let processor = MonitoringCycleProcessor(
            pendingActionVerifications: [
                PendingActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-A",
                    verifyAfter: Date(timeIntervalSince1970: 10)
                )
            ]
        )

        let result = processor.processScan(
            notifications: [notification],
            at: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(
            result.completedActionVerifications,
            [
                CompletedActionVerification(
                    actionRunID: 42,
                    notificationKey: "alert-A",
                    status: .definitelyFailed
                )
            ]
        )

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].type, .appeared)
    }

    func testDisappearanceGraceScansRemainPartOfCycleProcessing() {
        let notification = sampleNotification(key: "alert-A")

        let processor = MonitoringCycleProcessor(
            disappearanceGraceScans: 2
        )

        let appearedResult = processor.processScan(
            notifications: [notification],
            at: Date(timeIntervalSince1970: 10)
        )

        let firstMissingResult = processor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 20)
        )

        let secondMissingTimestamp = Date(
            timeIntervalSince1970: 30
        )

        let secondMissingResult = processor.processScan(
            notifications: [],
            at: secondMissingTimestamp
        )

        XCTAssertEqual(appearedResult.events.count, 1)
        XCTAssertEqual(appearedResult.events[0].type, .appeared)

        XCTAssertTrue(firstMissingResult.events.isEmpty)

        XCTAssertEqual(secondMissingResult.events.count, 1)
        XCTAssertEqual(
            secondMissingResult.events[0].type,
            .disappeared
        )
        XCTAssertEqual(
            secondMissingResult.events[0].notification.key,
            "alert-A"
        )
        XCTAssertEqual(
            secondMissingResult.events[0].timestamp,
            secondMissingTimestamp
        )
    }

    func testPreviousStateRecoveryOccursOnlyOnFirstCycle() {
        let notification = sampleNotification(key: "alert-A")

        let processor = MonitoringCycleProcessor(
            previouslyActive: [notification]
        )

        let firstResult = processor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 10)
        )

        let secondResult = processor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(firstResult.recoveredEvents.count, 1)
        XCTAssertTrue(secondResult.recoveredEvents.isEmpty)
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
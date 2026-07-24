import Foundation
@testable import NotilogCore
import XCTest

final class NotificationEventProcessorTests: XCTestCase {
    func testFirstScanRecoversPreviouslyActiveNotificationThatIsAbsent() {
        let notification = sampleNotification(key: "alert-A")
        let timestamp = Date(timeIntervalSince1970: 10)
        let processor = NotificationEventProcessor(
            previouslyActive: [notification]
        )

        let result = processor.processScan(
            notifications: [],
            at: timestamp
        )

        XCTAssertEqual(result.recoveredEvents.count, 1)
        XCTAssertEqual(
            result.recoveredEvents[0].type,
            .disappearedUnobserved
        )
        XCTAssertEqual(
            result.recoveredEvents[0].notification.key,
            "alert-A"
        )
        XCTAssertEqual(
            result.recoveredEvents[0].timestamp,
            timestamp
        )
        XCTAssertTrue(result.events.isEmpty)
    }

    func testPreviousStateRecoveryRunsOnlyOnce() {
        let notification = sampleNotification(key: "alert-A")
        let processor = NotificationEventProcessor(
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
        XCTAssertTrue(secondResult.events.isEmpty)
    }

    func testPreviouslyActiveNotificationStillVisibleIsNotRecovered() {
        let notification = sampleNotification(key: "alert-A")
        let timestamp = Date(timeIntervalSince1970: 10)
        let processor = NotificationEventProcessor(
            previouslyActive: [notification]
        )

        let result = processor.processScan(
            notifications: [notification],
            at: timestamp
        )

        XCTAssertTrue(result.recoveredEvents.isEmpty)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].type, .appeared)
        XCTAssertEqual(
            result.events[0].notification.key,
            "alert-A"
        )
        XCTAssertEqual(result.events[0].timestamp, timestamp)
    }

    func testDisappearanceUsesConfiguredGraceScans() {
        let notification = sampleNotification(key: "alert-A")
        let processor = NotificationEventProcessor(
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

    func testRecoveredAndCurrentEventsRemainSeparate() {
        let previousNotification = sampleNotification(
            key: "alert-A"
        )

        let currentNotification = sampleNotification(
            key: "alert-B"
        )

        let timestamp = Date(timeIntervalSince1970: 10)

        let processor = NotificationEventProcessor(
            previouslyActive: [previousNotification]
        )

        let result = processor.processScan(
            notifications: [currentNotification],
            at: timestamp
        )

        XCTAssertEqual(result.recoveredEvents.count, 1)
        XCTAssertEqual(
            result.recoveredEvents[0].type,
            .disappearedUnobserved
        )
        XCTAssertEqual(
            result.recoveredEvents[0].notification.key,
            "alert-A"
        )

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].type, .appeared)
        XCTAssertEqual(
            result.events[0].notification.key,
            "alert-B"
        )
    }

    private func sampleNotification(
        key: String,
        app: String = "Notigen",
        title: String = "Test notification",
        subtitle: String = "",
        body: String = "Test body"
    ) -> VisibleNotification {
        VisibleNotification(
            key: key,
            app: app,
            title: title,
            subtitle: subtitle,
            body: body
        )
    }
}
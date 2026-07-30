import XCTest
@testable import NotilogCore

final class NotificationMatchCriteriaTests: XCTestCase {
    func testMatchesAppEqualsIgnoringCaseByDefault() {
        let notification = sampleNotification(app: "Self Service+")

        let criteria = NotificationMatchCriteria(
            appEquals: "self service+"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testDoesNotMatchDifferentAppEquals() {
        let notification = sampleNotification(app: "Mail")

        let criteria = NotificationMatchCriteria(
            appEquals: "Slack"
        )

        XCTAssertFalse(criteria.matches(notification))
    }

    func testMatchesAppContains() {
        let notification = sampleNotification(app: "Self Service+")

        let criteria = NotificationMatchCriteria(
            appContains: "service"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testMatchesTitleEqualsIgnoringCaseByDefault() {
        let notification = sampleNotification(
            title: "Build Failed"
        )

        let criteria = NotificationMatchCriteria(
            titleEquals: "build failed"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testTitleEqualsDoesNotMatchPartialTitle() {
        let notification = sampleNotification(
            title: "Build Failed"
        )

        let criteria = NotificationMatchCriteria(
            titleEquals: "Build"
        )

        XCTAssertFalse(criteria.matches(notification))
    }

    func testMatchesSubtitleEquals() {
        let notification = sampleNotification(
            subtitle: "Update Available"
        )

        let criteria = NotificationMatchCriteria(
            subtitleEquals: "update available"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testMatchesBodyEquals() {
        let notification = sampleNotification(
            body: "Restart required."
        )

        let criteria = NotificationMatchCriteria(
            bodyEquals: "restart required."
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testMatchesTitleContains() {
        let notification = sampleNotification(
            title: "Microsoft Teams (work or school)"
        )

        let criteria = NotificationMatchCriteria(
            titleContains: "teams"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testMatchesBodyContains() {
        let notification = sampleNotification(
            body: "An update is available."
        )

        let criteria = NotificationMatchCriteria(
            bodyContains: "update"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testMatchesAnyTextContainsAcrossFields() {
        let notification = sampleNotification(
            app: "Self Service+",
            title: "Microsoft Teams",
            body: "An update is available."
        )

        let criteria = NotificationMatchCriteria(
            anyTextContains: "teams"
        )

        XCTAssertTrue(criteria.matches(notification))
    }

    func testAllCriteriaMustMatch() {
        let notification = sampleNotification(
            app: "Self Service+",
            title: "Microsoft Teams",
            body: "An update is available."
        )

        let criteria = NotificationMatchCriteria(
            appContains: "Self Service",
            titleContains: "Teams",
            bodyContains: "restart required"
        )

        XCTAssertFalse(criteria.matches(notification))
    }

    func testCaseSensitiveMatching() {
        let notification = sampleNotification(app: "Self Service+")

        let criteria = NotificationMatchCriteria(
            appEquals: "self service+",
            caseSensitive: true
        )

        XCTAssertFalse(criteria.matches(notification))
    }

    func testMatchesEventType() {
        let event = NotificationEvent(
            type: .appeared,
            notification: sampleNotification(),
            timestamp: Date()
        )

        let criteria = NotificationMatchCriteria(
            eventTypes: [.appeared]
        )

        XCTAssertTrue(criteria.matches(event))
    }

    func testDoesNotMatchDifferentEventType() {
        let event = NotificationEvent(
            type: .disappeared,
            notification: sampleNotification(),
            timestamp: Date()
        )

        let criteria = NotificationMatchCriteria(
            eventTypes: [.appeared]
        )

        XCTAssertFalse(criteria.matches(event))
    }

    private func sampleNotification(
        key: String = "AXNotificationCenterAlert|test-id",
        app: String = "Self Service+",
        title: String = "Microsoft Teams",
        subtitle: String = "",
        body: String = "An update is available."
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

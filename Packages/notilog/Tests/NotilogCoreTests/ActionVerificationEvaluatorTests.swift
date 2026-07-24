@testable import NotilogCore
import XCTest

final class ActionVerificationEvaluatorTests: XCTestCase {
    func testReturnsDefinitelyFailedWhenExactKeyStillExists() {
        let notification = VisibleNotification(
            key: "AXNotificationCenterAlert|ABC-123",
            app: "Notigen",
            title: "Test",
            subtitle: "",
            body: ""
        )

        let status = ActionVerificationEvaluator.evaluate(
            notificationKey: "AXNotificationCenterAlert|ABC-123",
            visibleNotifications: [notification]
        )

        XCTAssertEqual(status, .definitelyFailed)
    }

    func testReturnsProbablySucceededWhenExactKeyIsGone() {
        let otherNotification = VisibleNotification(
            key: "AXNotificationCenterAlert|OTHER-456",
            app: "Notigen",
            title: "Other notification",
            subtitle: "",
            body: ""
        )

        let status = ActionVerificationEvaluator.evaluate(
            notificationKey: "AXNotificationCenterAlert|ABC-123",
            visibleNotifications: [otherNotification]
        )

        XCTAssertEqual(status, .probablySucceeded)
    }
}

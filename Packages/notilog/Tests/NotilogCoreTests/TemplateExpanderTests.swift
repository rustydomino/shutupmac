import XCTest
@testable import NotilogCore

final class TemplateExpanderTests: XCTestCase {
    func testExpandsNotificationFields() {
        let event = sampleEvent(
            app: "Self Service+",
            title: "Microsoft Teams",
            body: "An update is available."
        )

        let expander = TemplateExpander()

        let result = expander.expand(
            "{{notification.app}} - {{notification.title}} - {{notification.body}}",
            for: event
        )

        XCTAssertEqual(
            result,
            "Self Service+ - Microsoft Teams - An update is available."
        )
    }

    func testExpandsAXIdentityFields() {
        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let expander = TemplateExpander()

        let result = expander.expand(
            "{{notification.subrole}} / {{notification.axIdentifier}} / {{notification.key}}",
            for: event
        )

        XCTAssertEqual(
            result,
            "AXNotificationCenterAlert / ABC-123 / AXNotificationCenterAlert|ABC-123"
        )
    }

    func testExpandsEventType() {
        let event = sampleEvent(type: .appeared)

        let expander = TemplateExpander()

        let result = expander.expand(
            "event={{event.type}}",
            for: event
        )

        XCTAssertEqual(result, "event=appeared")
    }

    func testLeavesUnknownPlaceholdersAlone() {
        let event = sampleEvent()

        let expander = TemplateExpander()

        let result = expander.expand(
            "unknown={{notification.nope}}",
            for: event
        )

        XCTAssertEqual(result, "unknown={{notification.nope}}")
    }

    private func sampleEvent(
        type: NotificationEventType = .appeared,
        key: String = "AXNotificationCenterAlert|test-id",
        app: String = "Self Service+",
        title: String = "Microsoft Teams",
        subtitle: String = "",
        body: String = "An update is available."
    ) -> NotificationEvent {
        let notification = VisibleNotification(
            key: key,
            app: app,
            title: title,
            subtitle: subtitle,
            body: body
        )

        return NotificationEvent(
            type: type,
            notification: notification,
            timestamp: Date(timeIntervalSince1970: 0)
        )
    }
}

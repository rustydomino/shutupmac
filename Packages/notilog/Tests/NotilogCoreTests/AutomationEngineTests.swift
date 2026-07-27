import XCTest
@testable import NotilogCore

final class AutomationEngineTests: XCTestCase {
    func testReturnsMatchWhenRuleCriteriaMatchesEvent() {
        let event = sampleEvent(
            type: .appeared,
            app: "Self Service+",
            title: "Microsoft Teams"
        )

        let rule = NotificationRule(
            id: UUID(),
            name: "Teams update",
            criteria: NotificationMatchCriteria(
                eventTypes: [.appeared],
                appContains: "Self Service",
                titleContains: "Teams"
            ),
            actions: [
                .dryRunLog(message: "would handle Teams update")
            ]
        )

        let engine = AutomationEngine(rules: [rule])
        let matches = engine.evaluate(event)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].ruleName, "Teams update")
        XCTAssertEqual(matches[0].action.summary, "would handle Teams update")
    }

    func testReturnsNoMatchWhenCriteriaDoesNotMatchEvent() {
        let event = sampleEvent(
            type: .appeared,
            app: "Mail",
            title: "Inbox"
        )

        let rule = NotificationRule(
            id: UUID(),
            name: "Teams update",
            criteria: NotificationMatchCriteria(
                appContains: "Self Service",
                titleContains: "Teams"
            ),
            actions: [
                .dryRunLog(message: "would handle Teams update")
            ]
        )

        let engine = AutomationEngine(rules: [rule])
        let matches = engine.evaluate(event)

        XCTAssertTrue(matches.isEmpty)
    }

    func testDisabledRuleDoesNotMatch() {
        let event = sampleEvent(
            type: .appeared,
            app: "Self Service+",
            title: "Microsoft Teams"
        )

        let rule = NotificationRule(
            id: UUID(),
            name: "Disabled rule",
            enabled: false,
            criteria: NotificationMatchCriteria(
                appContains: "Self Service"
            ),
            actions: [
                .dryRunLog(message: "should not run")
            ]
        )

        let engine = AutomationEngine(rules: [rule])
        let matches = engine.evaluate(event)

        XCTAssertTrue(matches.isEmpty)
    }

    func testMultipleActionsProduceMultipleMatches() {
        let event = sampleEvent(type: .appeared)

        let rule = NotificationRule(
            id: UUID(),
            name: "Multiple actions",
            criteria: NotificationMatchCriteria(
                eventTypes: [.appeared]
            ),
            actions: [
                .dryRunLog(message: "first action"),
                .dryRunLog(message: "second action")
            ]
        )

        let engine = AutomationEngine(rules: [rule])
        let matches = engine.evaluate(event)

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches[0].action.summary, "first action")
        XCTAssertEqual(matches[1].action.summary, "second action")
    }

    func testBuiltInRunProbeMatchesAppearedEvents() {
        let event = sampleEvent(type: .appeared)

        let engine = AutomationEngine.builtInProbe()
        let matches = engine.evaluate(event)

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].ruleName, "appeared notification")
        XCTAssertEqual(
            matches[0].action.summary,
            "/usr/bin/true --notification-key {{notification.key}}")
    }

    func testBuiltInProbeDoesNotMatchDisappearedEvents() {
        let event = sampleEvent(type: .disappeared)

        let engine = AutomationEngine.builtInProbe()
        let matches = engine.evaluate(event)

        XCTAssertTrue(matches.isEmpty)
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
            timestamp: Date()
        )
    }
}

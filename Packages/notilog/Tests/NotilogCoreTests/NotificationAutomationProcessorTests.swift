import Foundation
@testable import NotilogCore
import XCTest

final class NotificationAutomationProcessorTests: XCTestCase {
    func testDisabledModeReturnsNoResults() {
        let processor = makeProcessor(
            rules: [
                matchingRule(
                    name: "Matching rule",
                    actions: [
                        .dryRunLog(message: "should not run")
                    ]
                )
            ]
        )

        let results = processor.process(
            event: sampleEvent(),
            mode: .disabled
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testNonmatchingRuleReturnsNoResults() {
        let rule = NotificationRule(
            id: UUID(),
            name: "Mail only",
            criteria: NotificationMatchCriteria(
                appEquals: "Mail"
            ),
            actions: [
                .dryRunLog(message: "mail action")
            ]
        )

        let processor = makeProcessor(rules: [rule])

        let results = processor.process(
            event: sampleEvent(app: "Self Service+"),
            mode: .dryRun
        )

        XCTAssertTrue(results.isEmpty)
    }

    func testDryRunReturnsResolvedDryRunResult() {
        let processor = makeProcessor(
            rules: [
                matchingRule(
                    name: "Log notification",
                    actions: [
                        .dryRunLog(
                            message: "app={{notification.app}} key={{notification.key}}"
                        )
                    ]
                )
            ]
        )

        let results = processor.process(
            event: sampleEvent(
                key: "alert-A",
                app: "Notigen"
            ),
            mode: .dryRun
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].ruleName, "Log notification")
        XCTAssertEqual(results[0].status, .dryRun)
        XCTAssertEqual(
            results[0].resolvedAction,
            .dryRunLog(
                message: "app=Notigen key=alert-A"
            )
        )
        XCTAssertEqual(
            results[0].message,
            "would log: app=Notigen key=alert-A"
        )
    }

    func testRunActionsExecutesMatchingAction() {
        let processor = makeProcessor(
            rules: [
                matchingRule(
                    name: "Run log action",
                    actions: [
                        .dryRunLog(
                            message: "handled {{notification.title}}"
                        )
                    ]
                )
            ]
        )

        let results = processor.process(
            event: sampleEvent(title: "Test notification"),
            mode: .runActions
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].status, .succeeded)
        XCTAssertEqual(
            results[0].resolvedAction,
            .dryRunLog(
                message: "handled Test notification"
            )
        )
        XCTAssertEqual(
            results[0].message,
            "logged: handled Test notification"
        )
    }

    func testResultsPreserveRuleAndActionOrder() {
        let firstRule = matchingRule(
            name: "First rule",
            actions: [
                .dryRunLog(message: "first action"),
                .dryRunLog(message: "second action")
            ]
        )

        let secondRule = matchingRule(
            name: "Second rule",
            actions: [
                .dryRunLog(message: "third action")
            ]
        )

        let processor = makeProcessor(
            rules: [firstRule, secondRule]
        )

        let results = processor.process(
            event: sampleEvent(),
            mode: .dryRun
        )

        XCTAssertEqual(
            results.map(\.ruleName),
            [
                "First rule",
                "First rule",
                "Second rule"
            ]
        )

        XCTAssertEqual(
            results.map(\.resolvedAction),
            [
                .dryRunLog(message: "first action"),
                .dryRunLog(message: "second action"),
                .dryRunLog(message: "third action")
            ]
        )
    }

    func testDisabledRulesDoNotProduceResults() {
        let disabledRule = NotificationRule(
            id: UUID(),
            name: "Disabled rule",
            enabled: false,
            criteria: NotificationMatchCriteria(
                eventTypes: [.appeared]
            ),
            actions: [
                .dryRunLog(message: "should not run")
            ]
        )

        let processor = makeProcessor(
            rules: [disabledRule]
        )

        let results = processor.process(
            event: sampleEvent(),
            mode: .runActions
        )

        XCTAssertTrue(results.isEmpty)
    }

    private func makeProcessor(
        rules: [NotificationRule]
    ) -> NotificationAutomationProcessor {
        NotificationAutomationProcessor(
            engine: AutomationEngine(rules: rules)
        )
    }

    private func matchingRule(
        name: String,
        actions: [NotificationAction]
    ) -> NotificationRule {
        NotificationRule(
            id: UUID(),
            name: name,
            criteria: NotificationMatchCriteria(
                eventTypes: [.appeared]
            ),
            actions: actions
        )
    }

    private func sampleEvent(
        type: NotificationEventType = .appeared,
        key: String = "alert-A",
        app: String = "Self Service+",
        title: String = "Test notification",
        subtitle: String = "",
        body: String = "Test body"
    ) -> NotificationEvent {
        NotificationEvent(
            type: type,
            notification: VisibleNotification(
                key: key,
                app: app,
                title: title,
                subtitle: subtitle,
                body: body
            ),
            timestamp: Date(timeIntervalSince1970: 10)
        )
    }
}

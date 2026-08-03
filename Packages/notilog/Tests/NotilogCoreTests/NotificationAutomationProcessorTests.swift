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

    func testDisabledModeStillReportsMatchedRules() {
        let ruleID = UUID(
            uuidString: "00000000-0000-0000-0000-000000000201"
        )!

        let rule = NotificationRule(
            id: ruleID,
            name: "Matching rule",
            criteria: NotificationMatchCriteria(
                eventTypes: [.appeared]
            ),
            actions: [
                .dryRunLog(message: "should not run")
            ]
        )

        let processor = makeProcessor(rules: [rule])

        let result = processor.processDetailed(
            event: sampleEvent(),
            mode: .disabled
        )

        XCTAssertEqual(result.matchedRules.count, 1)
        XCTAssertEqual(result.matchedRules[0].ruleID, ruleID)
        XCTAssertEqual(
            result.matchedRules[0].ruleName,
            "Matching rule"
        )
        XCTAssertEqual(
            result.matchedRules[0].actions.count,
            1
        )

        XCTAssertTrue(result.actionResults.isEmpty)
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

    func testGuiAndCliProcessorsProduceIdenticalOutcomes() {
        let matchingRuleID = UUID(
            uuidString:
                "00000000-0000-0000-0000-000000000601"
        )!

        let nonmatchingRuleID = UUID(
            uuidString:
                "00000000-0000-0000-0000-000000000602"
        )!

        let rules = [
            NotificationRule(
                id: matchingRuleID,
                name: "Mail notification",
                criteria: NotificationMatchCriteria(
                    eventTypes: [.appeared],
                    appEquals: "Mail",
                    titleContains: "Invoice"
                ),
                actions: [
                    .dryRunLog(
                        message:
                            "Handled {{notification.key}}"
                    )
                ]
            ),

            NotificationRule(
                id: nonmatchingRuleID,
                name: "Messages notification",
                criteria: NotificationMatchCriteria(
                    eventTypes: [.appeared],
                    appEquals: "Messages"
                ),
                actions: [
                    .dryRunLog(
                        message: "Should not run"
                    )
                ]
            ),
        ]

        let event = sampleEvent(
            key: "invoice-alert",
            app: "Mail",
            title: "New Invoice"
        )

        for mode in [
            AutomationExecutionMode.dryRun,
            AutomationExecutionMode.runActions,
        ] {
            let guiProcessor =
                makeProcessor(rules: rules)

            let cliProcessor =
                makeProcessor(rules: rules)

            let guiResult =
                guiProcessor.processDetailed(
                    event: event,
                    mode: mode
                )

            let cliResult =
                cliProcessor.processDetailed(
                    event: event,
                    mode: mode
                )

            XCTAssertEqual(
                guiResult.matchedRules.map(\.ruleID),
                cliResult.matchedRules.map(\.ruleID)
            )

            XCTAssertEqual(
                guiResult.matchedRules.map(\.ruleName),
                cliResult.matchedRules.map(\.ruleName)
            )

            XCTAssertEqual(
                guiResult.matchedRules.map {
                    $0.actions.map(\.summary)
                },
                cliResult.matchedRules.map {
                    $0.actions.map(\.summary)
                }
            )

            XCTAssertEqual(
                guiResult.matchedRules.map(\.ruleID),
                [matchingRuleID]
            )

            XCTAssertEqual(
                guiResult.actionResults.count,
                1
            )

            XCTAssertEqual(
                cliResult.actionResults.count,
                1
            )

            let guiAction =
                guiResult.actionResults[0]

            let cliAction =
                cliResult.actionResults[0]

            XCTAssertEqual(
                guiAction.ruleName,
                cliAction.ruleName
            )

            XCTAssertEqual(
                guiAction.action.summary,
                cliAction.action.summary
            )

            XCTAssertEqual(
                guiAction.resolvedAction.summary,
                cliAction.resolvedAction.summary
            )

            XCTAssertEqual(
                guiAction.status,
                cliAction.status
            )

            XCTAssertEqual(
                guiAction.message,
                cliAction.message
            )

            XCTAssertEqual(
                guiAction.exitCode,
                cliAction.exitCode
            )

            XCTAssertEqual(
                guiAction.stdout,
                cliAction.stdout
            )

            XCTAssertEqual(
                guiAction.stderr,
                cliAction.stderr
            )

            XCTAssertEqual(
                guiAction.verificationStatus,
                cliAction.verificationStatus
            )
        }
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

    func testMultipleMatchingDismissRulesProduceOneDismissActionResult() {
        let firstRule = matchingRule(
            name: "First dismiss rule",
            actions: [
                .shutUpMacDismiss(
                    command: "/usr/bin/true"
                )
            ]
        )

        let secondRule = matchingRule(
            name: "Second dismiss rule",
            actions: [
                .shutUpMacDismiss(
                    command: "/usr/bin/true"
                )
            ]
        )

        let processor = makeProcessor(
            rules: [
                firstRule,
                secondRule
            ]
        )

        let result = processor.processDetailed(
            event: sampleEvent(
                key: "alert-A"
            ),
            mode: .dryRun
        )

        XCTAssertEqual(
            result.matchedRules.map(\.ruleName),
            [
                "First dismiss rule",
                "Second dismiss rule"
            ]
        )

        XCTAssertEqual(
            result.actionResults.count,
            1
        )

        XCTAssertEqual(
            result.actionResults[0].ruleName,
            "First dismiss rule"
        )

        XCTAssertEqual(
            result.actionResults[0].resolvedAction,
            .shutUpMacDismiss(
                command: "/usr/bin/true",
                notificationKey: "alert-A"
            )
        )
    }

    func testMultipleMatchingDismissRulesInvokeInjectedHandlerOnce() {
        let firstRule = matchingRule(
            name: "First dismiss rule",
            actions: [
                .shutUpMacDismiss(
                    command: "/usr/bin/false"
                )
            ]
        )

        let secondRule = matchingRule(
            name: "Second dismiss rule",
            actions: [
                .shutUpMacDismiss(
                    command: "/usr/bin/false"
                )
            ]
        )

        var receivedKeys: [String] = []

        let runner = ActionRunner(
            dismissalHandler: { key in
                receivedKeys.append(key)

                return NotificationDismissalResult(
                    succeeded: true,
                    message: "dismissed in process",
                    exitCode: 0
                )
            }
        )

        let processor = NotificationAutomationProcessor(
            engine: AutomationEngine(
                rules: [
                    firstRule,
                    secondRule
                ]
            ),
            runner: runner
        )

        let result = processor.processDetailed(
            event: sampleEvent(
                key: "alert-A"
            ),
            mode: .runActions
        )

        XCTAssertEqual(
            result.matchedRules.map(\.ruleName),
            [
                "First dismiss rule",
                "Second dismiss rule"
            ]
        )

        XCTAssertEqual(receivedKeys, ["alert-A"])
        XCTAssertEqual(result.actionResults.count, 1)
        XCTAssertEqual(
            result.actionResults[0].ruleName,
            "First dismiss rule"
        )
        XCTAssertEqual(
            result.actionResults[0].status,
            .succeeded
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

    func testReplaceEngineUsesNewRulesForSubsequentEvents() {
        let originalRule = NotificationRule(
            id: UUID(),
            name: "Mail rule",
            criteria: NotificationMatchCriteria(
                appEquals: "Mail"
            ),
            actions: [
                .dryRunLog(message: "matched Mail")
            ]
        )

        let replacementRule = NotificationRule(
            id: UUID(),
            name: "Messages rule",
            criteria: NotificationMatchCriteria(
                appEquals: "Messages"
            ),
            actions: [
                .dryRunLog(message: "matched Messages")
            ]
        )

        let processor = NotificationAutomationProcessor(
            engine: AutomationEngine(
                rules: [originalRule]
            )
        )

        let beforeReplacement = processor.processDetailed(
            event: sampleEvent(app: "Mail"),
            mode: .disabled
        )

        XCTAssertEqual(
            beforeReplacement.matchedRules.map(\.ruleName),
            ["Mail rule"]
        )

        processor.replaceEngine(
            AutomationEngine(
                rules: [replacementRule]
            )
        )

        let oldRuleAfterReplacement =
            processor.processDetailed(
                event: sampleEvent(app: "Mail"),
                mode: .disabled
            )

        XCTAssertTrue(
            oldRuleAfterReplacement.matchedRules.isEmpty
        )

        let newRuleAfterReplacement =
            processor.processDetailed(
                event: sampleEvent(app: "Messages"),
                mode: .disabled
            )

        XCTAssertEqual(
            newRuleAfterReplacement.matchedRules.map(\.ruleName),
            ["Messages rule"]
        )
    }

    func testInvalidConfigurationLeavesCurrentEngineActive() {
        let originalRule = NotificationRule(
            id: UUID(),
            name: "Original Mail rule",
            criteria: NotificationMatchCriteria(
                appEquals: "Mail"
            ),
            actions: [
                .dryRunLog(message: "matched Mail")
            ]
        )

        let processor = makeProcessor(
            rules: [originalRule]
        )

        let invalidConfiguration = AutomationConfig(
            rules: [
                AutomationRuleConfig(
                    id: UUID(),
                    name: "Invalid replacement rule",
                    enabled: true,
                    match: NotificationMatchConfig(
                        eventTypes: [.appeared],
                        appEquals: "Messages",
                        appContains: nil,
                        titleContains: nil,
                        subtitleContains: nil,
                        bodyContains: nil,
                        anyTextContains: nil,
                        caseSensitive: false
                    ),
                    actions: [
                        NotificationActionConfig(
                            type: "exec",
                            message: nil,
                            command: nil,
                            arguments: nil
                        )
                    ]
                )
            ]
        )

        XCTAssertThrowsError(
            try processor.replaceConfiguration(
                invalidConfiguration
            )
        ) { error in
            XCTAssertEqual(
                error as? AutomationConfigError,
                .missingExecCommand
            )
        }

        let result = processor.processDetailed(
            event: sampleEvent(app: "Mail"),
            mode: .disabled
        )

        XCTAssertEqual(
            result.matchedRules.map(\.ruleName),
            ["Original Mail rule"]
        )
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

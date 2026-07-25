import Foundation
@testable import NotilogCore
import XCTest

final class NotificationMonitorTests: XCTestCase {
    func testProcessScanCoordinatesAllResultTypesInOrder()
        throws
    {
        let previousNotification = sampleNotification(
            key: "alert-previous"
        )

        let currentNotification = sampleNotification(
            key: "alert-current"
        )

        let components = makeMonitor(
            rules: [
                matchingRule(
                    name: "Log all events",
                    eventTypes: [
                        .disappearedUnobserved,
                        .appeared
                    ],
                    actions: [
                        .dryRunLog(
                            message:
                                "handled {{notification.key}}"
                        )
                    ]
                )
            ],
            automationMode: .dryRun,
            previouslyActive: [previousNotification],
            pendingActionVerifications: [
                PendingActionVerification(
                    actionRunID: nil,
                    notificationKey: "alert-dismissed",
                    verifyAfter: Date(
                        timeIntervalSince1970: 10
                    )
                )
            ]
        )

        var callbackOrder: [String] = []

        let result = try components.monitor.processScan(
            notifications: [currentNotification],
            at: Date(timeIntervalSince1970: 10),
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
            },
            afterCompletedActionVerifications: {
                verifications in

                callbackOrder.append(
                    "verification:\(verifications[0].notificationKey)"
                )
            },
            beforeAutomation: { event in
                callbackOrder.append(
                    "event:\(event.notification.key)"
                )
            },
            beforeActionResultCoordination: {
                actionResult in

                callbackOrder.append(
                    "action:\(actionResult.event.notification.key)"
                )
            },
            afterRecoveredEvents: {
                recoveredEvents in

                callbackOrder.append(
                    "recovered:\(recoveredEvents[0].event.notification.key)"
                )
            }
        )

        XCTAssertEqual(
            callbackOrder,
            [
                "verification:alert-dismissed",
                "event:alert-previous",
                "action:alert-previous",
                "recovered:alert-previous",
                "event:alert-current",
                "action:alert-current"
            ]
        )

        XCTAssertEqual(
            result.completedActionVerifications,
            [
                CompletedActionVerification(
                    actionRunID: nil,
                    notificationKey: "alert-dismissed",
                    status: .probablySucceeded
                )
            ]
        )

        XCTAssertEqual(result.recoveredEvents.count, 1)
        XCTAssertEqual(
            result.recoveredEvents[0]
                .event
                .notification
                .key,
            "alert-previous"
        )
        XCTAssertEqual(
            result.recoveredEvents[0].actionResults.count,
            1
        )

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(
            result.events[0].event.notification.key,
            "alert-current"
        )
        XCTAssertEqual(
            result.events[0].actionResults.count,
            1
        )
    }

    func testRecoveredCallbackRunsBeforeCurrentEventsWhenEmpty()
        throws
    {
        let components = makeMonitor(
            rules: [],
            automationMode: .disabled
        )

        var callbackOrder: [String] = []

        let result = try components.monitor.processScan(
            notifications: [
                sampleNotification(key: "alert-A")
            ],
            at: Date(timeIntervalSince1970: 10),
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
            },
            afterCompletedActionVerifications: {
                verifications in

                XCTAssertTrue(verifications.isEmpty)

                callbackOrder.append(
                    "verifications"
                )
            },
            beforeAutomation: { event in
                callbackOrder.append(
                    "event:\(event.notification.key)"
                )
            },
            beforeActionResultCoordination: { _ in
                XCTFail(
                    "Disabled automation should not produce actions"
                )
            },
            afterRecoveredEvents: {
                recoveredEvents in

                XCTAssertTrue(recoveredEvents.isEmpty)

                callbackOrder.append(
                    "recovered"
                )
            }
        )

        XCTAssertEqual(
            callbackOrder,
            [
                "verifications",
                "recovered",
                "event:alert-A"
            ]
        )

        XCTAssertTrue(result.recoveredEvents.isEmpty)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertTrue(
            result.events[0].actionResults.isEmpty
        )
    }

    func testActionTimestampProviderControlsVerification()
        throws
    {
        let components = makeMonitor(
            rules: [
                matchingRule(
                    name: "Dismiss notification",
                    eventTypes: [.appeared],
                    actions: [
                        .shutUpMacDismiss(
                            command: "/usr/bin/true"
                        )
                    ]
                )
            ],
            automationMode: .runActions,
            dismissalVerificationDelay: 2
        )

        let firstResult =
            try components.monitor.processScan(
                notifications: [
                    sampleNotification(key: "alert-A")
                ],
                at: Date(timeIntervalSince1970: 5),
                actionTimestampProvider: {
                    Date(timeIntervalSince1970: 10)
                },
                afterCompletedActionVerifications: {
                    _ in
                },
                beforeAutomation: { _ in },
                beforeActionResultCoordination: {
                    _ in
                },
                afterRecoveredEvents: { _ in }
            )

        XCTAssertEqual(firstResult.events.count, 1)
        XCTAssertEqual(
            firstResult.events[0].actionResults.count,
            1
        )
        XCTAssertEqual(
            firstResult.events[0]
                .actionResults[0]
                .result
                .verificationStatus,
            .pending
        )

        let earlyResult =
            try components.monitor.processScan(
                notifications: [],
                at: Date(timeIntervalSince1970: 11),
                actionTimestampProvider: {
                    Date(timeIntervalSince1970: 20)
                },
                afterCompletedActionVerifications: {
                    _ in
                },
                beforeAutomation: { _ in },
                beforeActionResultCoordination: {
                    _ in
                },
                afterRecoveredEvents: { _ in }
            )

        XCTAssertTrue(
            earlyResult
                .completedActionVerifications
                .isEmpty
        )

        let dueResult =
            try components.monitor.processScan(
                notifications: [],
                at: Date(timeIntervalSince1970: 12),
                actionTimestampProvider: {
                    Date(timeIntervalSince1970: 20)
                },
                afterCompletedActionVerifications: {
                    _ in
                },
                beforeAutomation: { _ in },
                beforeActionResultCoordination: {
                    _ in
                },
                afterRecoveredEvents: { _ in }
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

    func testDisabledAutomationReturnsEventsWithoutActions()
        throws
    {
        let components = makeMonitor(
            rules: [
                matchingRule(
                    name: "Should not run",
                    eventTypes: [.appeared],
                    actions: [
                        .dryRunLog(
                            message: "should not run"
                        )
                    ]
                )
            ],
            automationMode: .disabled
        )

        var renderedKeys: [String] = []

        let result = try components.monitor.processScan(
            notifications: [
                sampleNotification(key: "alert-A"),
                sampleNotification(key: "alert-B")
            ],
            at: Date(timeIntervalSince1970: 10),
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
            },
            afterCompletedActionVerifications: {
                _ in
            },
            beforeAutomation: { event in
                renderedKeys.append(
                    event.notification.key
                )
            },
            beforeActionResultCoordination: { _ in
                XCTFail(
                    "Disabled automation should not produce actions"
                )
            },
            afterRecoveredEvents: { _ in }
        )

        XCTAssertEqual(
            renderedKeys,
            ["alert-A", "alert-B"]
        )

        XCTAssertEqual(result.events.count, 2)
        XCTAssertTrue(
            result.events.allSatisfy {
                $0.actionResults.isEmpty
            }
        )
    }

    private func makeMonitor(
        rules: [NotificationRule],
        automationMode: AutomationExecutionMode,
        previouslyActive: [VisibleNotification] = [],
        pendingActionVerifications:
            [PendingActionVerification] = [],
        dismissalVerificationDelay:
            TimeInterval = 2
    ) -> (
        monitor: NotificationMonitor,
        cycleProcessor: MonitoringCycleProcessor
    ) {
        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let cycleProcessor = MonitoringCycleProcessor(
            previouslyActive: previouslyActive,
            pendingActionVerifications:
                pendingActionVerifications
        )

        let persistenceCoordinator =
            NotificationEventPersistenceCoordinator(
                store: nil,
                session: session,
                redactionPolicy: .disabled
            )

        let automationProcessor =
            NotificationAutomationProcessor(
                engine: AutomationEngine(
                    rules: rules
                )
            )

        let actionResultCoordinator =
            ActionResultCoordinator(
                store: nil,
                session: session,
                redactionPolicy: .disabled,
                cycleProcessor: cycleProcessor,
                dismissalVerificationDelay:
                    dismissalVerificationDelay
            )

        let eventCoordinator =
            NotificationEventCoordinator(
                persistenceCoordinator:
                    persistenceCoordinator,
                automationProcessor:
                    automationProcessor,
                actionResultCoordinator:
                    actionResultCoordinator
            )

        let completedVerificationCoordinator =
            CompletedActionVerificationCoordinator(
                store: nil
            )

        let monitor = NotificationMonitor(
            cycleProcessor: cycleProcessor,
            completedVerificationCoordinator:
                completedVerificationCoordinator,
            eventCoordinator: eventCoordinator,
            automationMode: automationMode
        )

        return (
            monitor: monitor,
            cycleProcessor: cycleProcessor
        )
    }

    private func matchingRule(
        name: String,
        eventTypes: [NotificationEventType],
        actions: [NotificationAction]
    ) -> NotificationRule {
        NotificationRule(
            name: name,
            criteria: NotificationMatchCriteria(
                eventTypes: eventTypes
            ),
            actions: actions
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
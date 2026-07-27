import Foundation
@testable import NotilogCore
import XCTest

final class NotificationEventCoordinatorTests: XCTestCase {
    func testEventBatchIsPersistedBeforeEventCallback() throws {
        let temporaryDirectory = try makeTemporaryDirectory()

        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let store = try NotificationStore(
            path: temporaryDirectory
                .appendingPathComponent("notilog.sqlite")
                .path
        )

        let session = testSession()

        let coordinator = makeCoordinator(
            rules: [],
            store: store,
            session: session
        ).coordinator

        let event = sampleEvent(key: "alert-A")
        var eventWasAlreadyStored = false

        _ = try coordinator.process(
            [event],
            automationMode: .disabled,
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
            },
            beforeAutomation: { _ in
                let records = try? store.recentEvents(
                    limit: 10
                )

                eventWasAlreadyStored =
                    records?.contains {
                        $0.event.notification.key == "alert-A"
                    } ?? false
            },
            beforeActionResultCoordination: { _ in
                XCTFail(
                    "Disabled automation should not produce actions"
                )
            }
        )

        XCTAssertTrue(eventWasAlreadyStored)
    }

    func testCallbacksAndResultsPreserveEventAndActionOrder()
        throws
    {
        let rule = matchingRule(
            name: "Ordered actions",
            actions: [
                .dryRunLog(
                    message: "first {{notification.key}}"
                ),
                .dryRunLog(
                    message: "second {{notification.key}}"
                )
            ]
        )

        let coordinator = makeCoordinator(
            rules: [rule]
        ).coordinator

        let firstEvent = sampleEvent(key: "alert-A")
        let secondEvent = sampleEvent(key: "alert-B")

        var callbackOrder: [String] = []

        let coordinatedEvents = try coordinator.process(
            [firstEvent, secondEvent],
            automationMode: .dryRun,
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
            },
            beforeAutomation: { event in
                callbackOrder.append(
                    "event:\(event.notification.key)"
                )
            },
            beforeActionResultCoordination: { result in
                callbackOrder.append(
                    "action:\(result.event.notification.key):\(result.message)"
                )
            }
        )

        XCTAssertEqual(
            callbackOrder,
            [
                "event:alert-A",
                "action:alert-A:would log: first alert-A",
                "action:alert-A:would log: second alert-A",
                "event:alert-B",
                "action:alert-B:would log: first alert-B",
                "action:alert-B:would log: second alert-B"
            ]
        )

        XCTAssertEqual(
            coordinatedEvents.map {
                $0.event.notification.key
            },
            ["alert-A", "alert-B"]
        )

        XCTAssertEqual(
            coordinatedEvents.map {
                $0.actionResults.count
            },
            [2, 2]
        )

        XCTAssertEqual(
            coordinatedEvents[0].actionResults.map {
                $0.result.message
            },
            [
                "would log: first alert-A",
                "would log: second alert-A"
            ]
        )
    }

    func testActionCallbackRunsBeforeActionPersistence() throws {
        let temporaryDirectory = try makeTemporaryDirectory()

        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let store = try NotificationStore(
            path: temporaryDirectory
                .appendingPathComponent("notilog.sqlite")
                .path
        )

        let rule = matchingRule(
            name: "Log action",
            actions: [
                .dryRunLog(message: "handled")
            ]
        )

        let coordinator = makeCoordinator(
            rules: [rule],
            store: store
        ).coordinator

        var storedActionCountDuringCallback: Int?

        _ = try coordinator.process(
            [sampleEvent(key: "alert-A")],
            automationMode: .runActions,
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
            },
            beforeAutomation: { _ in },
            beforeActionResultCoordination: { _ in
                storedActionCountDuringCallback =
                    try? store.recentActionRuns(
                        limit: 10
                    ).count
            }
        )

        XCTAssertEqual(
            storedActionCountDuringCallback,
            0
        )

        let storedActions = try store.recentActionRuns(
            limit: 10
        )

        XCTAssertEqual(storedActions.count, 1)
        XCTAssertEqual(
            storedActions[0].ruleName,
            "Log action"
        )
    }

    func testTimestampProviderControlsVerificationSchedule()
        throws
    {
        let components = makeCoordinator(
            rules: [
                matchingRule(
                    name: "Dismiss notification",
                    actions: [
                        .shutUpMacDismiss(
                            command: "/usr/bin/true"
                        )
                    ]
                )
            ],
            dismissalVerificationDelay: 2
        )

        let timestamp = Date(timeIntervalSince1970: 10)

        let coordinatedEvents = try components.coordinator.process(
            [sampleEvent(key: "alert-A")],
            automationMode: .runActions,
            actionTimestampProvider: {
                timestamp
            },
            beforeAutomation: { _ in },
            beforeActionResultCoordination: { _ in }
        )

        XCTAssertEqual(
            coordinatedEvents[0].actionResults.count,
            1
        )

        XCTAssertEqual(
            coordinatedEvents[0]
                .actionResults[0]
                .result
                .verificationStatus,
            .pending
        )

        let earlyCycle = components.cycleProcessor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 11)
        )

        XCTAssertTrue(
            earlyCycle.completedActionVerifications.isEmpty
        )

        let dueCycle = components.cycleProcessor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(
            dueCycle.completedActionVerifications,
            [
                CompletedActionVerification(
                    actionRunID: nil,
                    notificationKey: "alert-A",
                    status: .probablySucceeded
                )
            ]
        )
    }

    func testDisabledAutomationStillPersistsAndReturnsEvents()
        throws
    {
        let temporaryDirectory = try makeTemporaryDirectory()

        defer {
            try? FileManager.default.removeItem(
                at: temporaryDirectory
            )
        }

        let store = try NotificationStore(
            path: temporaryDirectory
                .appendingPathComponent("notilog.sqlite")
                .path
        )

        let rule = matchingRule(
            name: "Should not run",
            actions: [
                .dryRunLog(message: "should not run")
            ]
        )

        let coordinator = makeCoordinator(
            rules: [rule],
            store: store
        ).coordinator

        var renderedKeys: [String] = []

        let results = try coordinator.process(
            [
                sampleEvent(key: "alert-A"),
                sampleEvent(key: "alert-B")
            ],
            automationMode: .disabled,
            actionTimestampProvider: {
                Date(timeIntervalSince1970: 20)
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
            }
        )

        XCTAssertEqual(
            renderedKeys,
            ["alert-A", "alert-B"]
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].actionResults.isEmpty)
        XCTAssertTrue(results[1].actionResults.isEmpty)

        let records = try store.recentEvents(limit: 10)

        XCTAssertEqual(
            records.map {
                $0.event.notification.key
            },
            ["alert-A", "alert-B"]
        )

        XCTAssertTrue(
            try store.recentActionRuns(limit: 10).isEmpty
        )
    }

    private func makeCoordinator(
        rules: [NotificationRule],
        store: NotificationStore? = nil,
        session: ObservationSession? = nil,
        dismissalVerificationDelay: TimeInterval = 2
    ) -> (
        coordinator: NotificationEventCoordinator,
        cycleProcessor: MonitoringCycleProcessor
    ) {
        let resolvedSession = session ?? testSession()
        let cycleProcessor = MonitoringCycleProcessor()

        let persistenceCoordinator =
            NotificationEventPersistenceCoordinator(
                store: store,
                session: resolvedSession,
                redactionPolicy: .disabled
            )

        let automationProcessor =
            NotificationAutomationProcessor(
                engine: AutomationEngine(rules: rules)
            )

        let actionResultCoordinator =
            ActionResultCoordinator(
                store: store,
                session: resolvedSession,
                redactionPolicy: .disabled,
                cycleProcessor: cycleProcessor,
                dismissalVerificationDelay:
                    dismissalVerificationDelay
            )

        let coordinator = NotificationEventCoordinator(
            persistenceCoordinator: persistenceCoordinator,
            automationProcessor: automationProcessor,
            actionResultCoordinator: actionResultCoordinator
        )

        return (
            coordinator: coordinator,
            cycleProcessor: cycleProcessor
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
        key: String
    ) -> NotificationEvent {
        NotificationEvent(
            type: .appeared,
            notification: VisibleNotification(
                key: key,
                app: "Notigen",
                title: "Test notification",
                subtitle: "",
                body: "Test body"
            ),
            timestamp: Date(timeIntervalSince1970: 5)
        )
    }

    private func testSession() -> ObservationSession {
        ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString)",
                isDirectory: true
            )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        return directory
    }
}

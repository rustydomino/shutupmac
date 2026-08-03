import Foundation
@testable import NotilogCore
import XCTest

final class ActionResultCoordinatorTests: XCTestCase {
    func testNoLoggingPreservesNilIDAndSchedulesVerification() throws {
        let cycleProcessor = MonitoringCycleProcessor()

        let coordinator = ActionResultCoordinator(
            store: nil,
            session: testSession(),
            redactionPolicy: .disabled,
            cycleProcessor: cycleProcessor,
            dismissalVerificationDelay: 2
        )

        let result = sampleResult(
            notificationKey: "alert-A",
            verificationStatus: .pending
        )

        let coordinatedResults = try coordinator.process(
            [result],
            at: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(coordinatedResults.count, 1)
        XCTAssertNil(coordinatedResults[0].actionRunID)
        XCTAssertEqual(
            coordinatedResults[0].result.ruleName,
            "Dismiss notification"
        )

        let earlyCycle = cycleProcessor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 11)
        )

        XCTAssertTrue(
            earlyCycle.completedActionVerifications.isEmpty
        )

        let dueCycle = cycleProcessor.processScan(
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

    func testLoggingPersistsResultAndSchedulesUsingStoredID() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let cycleProcessor = MonitoringCycleProcessor()

        let coordinator = ActionResultCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: .disabled,
            cycleProcessor: cycleProcessor,
            dismissalVerificationDelay: 2
        )

        let coordinatedResults = try coordinator.process(
            [
                sampleResult(
                    notificationKey: "alert-A",
                    verificationStatus: .pending
                )
            ],
            at: Date(timeIntervalSince1970: 10)
        )

        let actionRunID = try XCTUnwrap(
            coordinatedResults.first?.actionRunID
        )

        XCTAssertGreaterThan(actionRunID, 0)

        let storedRecords = try store.recentActionRuns(limit: 10)

        XCTAssertEqual(storedRecords.count, 1)
        XCTAssertEqual(storedRecords[0].id, actionRunID)
        XCTAssertEqual(
            storedRecords[0].verificationStatus,
            .pending
        )

        let dueCycle = cycleProcessor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 12)
        )

        XCTAssertEqual(
            dueCycle.completedActionVerifications,
            [
                CompletedActionVerification(
                    actionRunID: actionRunID,
                    notificationKey: "alert-A",
                    status: .probablySucceeded
                )
            ]
        )
    }

    func testRedactionIsAppliedToStorageButNotReturnedResult() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = ActionResultCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: RedactionPolicy(
                fields: [.title, .body]
            ),
            cycleProcessor: MonitoringCycleProcessor(),
            dismissalVerificationDelay: 2
        )

        let originalResult = sampleResult(
            title: "Secret title",
            body: "Secret body",
            message: "Original detailed message",
            stdout: "Secret stdout",
            stderr: "Secret stderr",
            verificationStatus: nil
        )

        let coordinatedResults = try coordinator.process(
            [originalResult],
            at: Date(timeIntervalSince1970: 10)
        )

        let returnedResult = coordinatedResults[0].result

        XCTAssertEqual(
            returnedResult.event.notification.title,
            "Secret title"
        )
        XCTAssertEqual(
            returnedResult.event.notification.body,
            "Secret body"
        )
        XCTAssertEqual(
            returnedResult.message,
            "Original detailed message"
        )
        XCTAssertEqual(returnedResult.stdout, "Secret stdout")
        XCTAssertEqual(returnedResult.stderr, "Secret stderr")

        let records = try store.recentActionRuns(limit: 10)
        let storedRecord = try XCTUnwrap(records.first)

        XCTAssertEqual(
            storedRecord.notification.title,
            "[REDACTED]"
        )
        XCTAssertEqual(
            storedRecord.notification.body,
            "[REDACTED]"
        )
        XCTAssertEqual(
            storedRecord.message,
            "status: succeeded, exit code: 0"
        )
        XCTAssertEqual(
            storedRecord.stdout,
            "[SUPPRESSED BY REDACTION]"
        )
        XCTAssertEqual(
            storedRecord.stderr,
            "[SUPPRESSED BY REDACTION]"
        )
    }

    func testReplacingRedactionPolicyAffectsOnlySubsequentActionWrites() throws {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = ActionResultCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: .disabled,
            cycleProcessor: MonitoringCycleProcessor(),
            dismissalVerificationDelay: 2
        )

        let firstResult = sampleResult(
            notificationKey: "alert-A",
            title: "First secret title",
            body: "First secret body",
            message: "First detailed message",
            stdout: "First secret stdout",
            stderr: "First secret stderr"
        )

        let firstCoordinatedResult = try XCTUnwrap(
            coordinator.process(
                [firstResult],
                at: Date(timeIntervalSince1970: 10)
            ).first
        )

        coordinator.replaceRedactionPolicy(
            RedactionPolicy(
                fields: [.title, .body]
            )
        )

        let secondResult = sampleResult(
            notificationKey: "alert-B",
            title: "Second secret title",
            body: "Second secret body",
            message: "Second detailed message",
            stdout: "Second secret stdout",
            stderr: "Second secret stderr"
        )

        let secondCoordinatedResult = try XCTUnwrap(
            coordinator.process(
                [secondResult],
                at: Date(timeIntervalSince1970: 20)
            ).first
        )

        let records = try store.recentActionRuns(limit: 10)

        XCTAssertEqual(records.count, 2)

        let firstRecord = records[0]

        XCTAssertEqual(
            firstRecord.notification.key,
            "alert-A"
        )
        XCTAssertEqual(
            firstRecord.notification.title,
            "First secret title"
        )
        XCTAssertEqual(
            firstRecord.notification.body,
            "First secret body"
        )
        XCTAssertEqual(
            firstRecord.message,
            "First detailed message"
        )
        XCTAssertEqual(
            firstRecord.stdout,
            "First secret stdout"
        )
        XCTAssertEqual(
            firstRecord.stderr,
            "First secret stderr"
        )

        let secondRecord = records[1]

        XCTAssertEqual(
            secondRecord.notification.key,
            "alert-B"
        )
        XCTAssertEqual(
            secondRecord.notification.app,
            "Notigen"
        )
        XCTAssertEqual(
            secondRecord.notification.title,
            "[REDACTED]"
        )
        XCTAssertEqual(
            secondRecord.notification.body,
            "[REDACTED]"
        )
        XCTAssertEqual(
            secondRecord.message,
            "status: succeeded, exit code: 0"
        )
        XCTAssertEqual(
            secondRecord.stdout,
            "[SUPPRESSED BY REDACTION]"
        )
        XCTAssertEqual(
            secondRecord.stderr,
            "[SUPPRESSED BY REDACTION]"
        )

        XCTAssertEqual(
            firstCoordinatedResult.result.event.notification.title,
            "First secret title"
        )
        XCTAssertEqual(
            firstCoordinatedResult.result.message,
            "First detailed message"
        )
        XCTAssertEqual(
            firstCoordinatedResult.result.stdout,
            "First secret stdout"
        )
        XCTAssertEqual(
            firstCoordinatedResult.result.stderr,
            "First secret stderr"
        )

        XCTAssertEqual(
            secondCoordinatedResult.result.event.notification.title,
            "Second secret title"
        )
        XCTAssertEqual(
            secondCoordinatedResult.result.event.notification.body,
            "Second secret body"
        )
        XCTAssertEqual(
            secondCoordinatedResult.result.message,
            "Second detailed message"
        )
        XCTAssertEqual(
            secondCoordinatedResult.result.stdout,
            "Second secret stdout"
        )
        XCTAssertEqual(
            secondCoordinatedResult.result.stderr,
            "Second secret stderr"
        )
    }

    func testResultWithoutPendingVerificationIsNotScheduled() throws {
        let cycleProcessor = MonitoringCycleProcessor()

        let coordinator = ActionResultCoordinator(
            store: nil,
            session: testSession(),
            redactionPolicy: .disabled,
            cycleProcessor: cycleProcessor,
            dismissalVerificationDelay: 2
        )

        _ = try coordinator.process(
            [
                sampleResult(
                    verificationStatus: nil
                )
            ],
            at: Date(timeIntervalSince1970: 10)
        )

        let laterCycle = cycleProcessor.processScan(
            notifications: [],
            at: Date(timeIntervalSince1970: 20)
        )

        XCTAssertTrue(
            laterCycle.completedActionVerifications.isEmpty
        )
    }

    func testMixedUnredactedRedactedAndTruncatedActionRunsRemainQueryable()
        throws
    {
        let databaseURL = temporaryDatabaseURL()

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let coordinator = ActionResultCoordinator(
            store: store,
            session: testSession(),
            redactionPolicy: .disabled,
            cycleProcessor:
                MonitoringCycleProcessor(),
            dismissalVerificationDelay: 2
        )

        try coordinator.process(
            [
                sampleResult(
                    notificationKey:
                        "alert-unredacted",
                    title: "Visible title",
                    body: "Visible body",
                    message: "Visible message",
                    stdout: "Visible stdout",
                    stderr: "Visible stderr"
                )
            ],
            at: Date(timeIntervalSince1970: 10)
        )

        coordinator.replaceRedactionPolicy(
            RedactionPolicy(
                fields: [
                    .title,
                    .body,
                ]
            )
        )

        try coordinator.process(
            [
                sampleResult(
                    notificationKey:
                        "alert-redacted",
                    title: "Secret title",
                    body: "Secret body",
                    message: "Secret message",
                    stdout: "Secret stdout",
                    stderr: "Secret stderr"
                )
            ],
            at: Date(timeIntervalSince1970: 20)
        )

        coordinator.replaceRedactionPolicy(
            .disabled
        )

        let longTitle =
            String(
                repeating: "T",
                count: 5_000
            )

        let longBody =
            String(
                repeating: "B",
                count: 5_000
            )

        let longMessage =
            String(
                repeating: "M",
                count: 5_000
            )

        let longStandardOutput =
            String(
                repeating: "O",
                count: 5_000
            )

        let longStandardError =
            String(
                repeating: "E",
                count: 5_000
            )

        try coordinator.process(
            [
                sampleResult(
                    notificationKey:
                        "alert-truncated",
                    title: longTitle,
                    body: longBody,
                    message: longMessage,
                    stdout: longStandardOutput,
                    stderr: longStandardError
                )
            ],
            at: Date(timeIntervalSince1970: 30)
        )

        let records =
            try store.recentActionRuns(
                limit: 10
            )

        XCTAssertEqual(
            records.map {
                $0.notification.key
            },
            [
                "alert-unredacted",
                "alert-redacted",
                "alert-truncated",
            ]
        )

        let unredacted = records[0]

        XCTAssertEqual(
            unredacted.notification.title,
            "Visible title"
        )

        XCTAssertEqual(
            unredacted.notification.body,
            "Visible body"
        )

        XCTAssertEqual(
            unredacted.message,
            "Visible message"
        )

        XCTAssertEqual(
            unredacted.stdout,
            "Visible stdout"
        )

        XCTAssertEqual(
            unredacted.stderr,
            "Visible stderr"
        )

        let redacted = records[1]

        XCTAssertEqual(
            redacted.notification.title,
            "[REDACTED]"
        )

        XCTAssertEqual(
            redacted.notification.body,
            "[REDACTED]"
        )

        XCTAssertEqual(
            redacted.message,
            "status: succeeded, exit code: 0"
        )

        XCTAssertEqual(
            redacted.stdout,
            "[SUPPRESSED BY REDACTION]"
        )

        XCTAssertEqual(
            redacted.stderr,
            "[SUPPRESSED BY REDACTION]"
        )

        let truncated = records[2]

        XCTAssertEqual(
            truncated.notification.title,
            String(longTitle.prefix(4_096))
        )

        XCTAssertEqual(
            truncated.notification.body,
            String(longBody.prefix(4_096))
        )

        XCTAssertEqual(
            truncated.message,
            String(longMessage.prefix(4_096))
        )

        XCTAssertEqual(
            truncated.stdout,
            String(
                longStandardOutput.prefix(4_096)
            )
        )

        XCTAssertEqual(
            truncated.stderr,
            String(
                longStandardError.prefix(4_096)
            )
        )
    }

    func testResultsPreserveInputOrder() throws {
        let coordinator = ActionResultCoordinator(
            store: nil,
            session: testSession(),
            redactionPolicy: .disabled,
            cycleProcessor: MonitoringCycleProcessor(),
            dismissalVerificationDelay: 2
        )

        let coordinatedResults = try coordinator.process(
            [
                sampleResult(
                    ruleName: "First rule",
                    notificationKey: "alert-A"
                ),
                sampleResult(
                    ruleName: "Second rule",
                    notificationKey: "alert-B"
                )
            ],
            at: Date(timeIntervalSince1970: 10)
        )

        XCTAssertEqual(
            coordinatedResults.map { $0.result.ruleName },
            ["First rule", "Second rule"]
        )
    }

    private func sampleResult(
        ruleName: String = "Dismiss notification",
        notificationKey: String = "alert-A",
        title: String = "Test notification",
        body: String = "Test body",
        message: String = "Dismissal request accepted",
        stdout: String = "",
        stderr: String = "",
        verificationStatus: ActionVerificationStatus? = nil
    ) -> ActionRunResult {
        let notification = VisibleNotification(
            key: notificationKey,
            app: "Notigen",
            title: title,
            subtitle: "",
            body: body
        )

        let event = NotificationEvent(
            type: .appeared,
            notification: notification,
            timestamp: Date(timeIntervalSince1970: 5)
        )

        return ActionRunResult(
            ruleName: ruleName,
            action: .shutUpMacDismiss(
                command: "/usr/bin/true"
            ),
            resolvedAction: .shutUpMacDismiss(
                command: "/usr/bin/true",
                notificationKey: notificationKey
            ),
            event: event,
            status: .succeeded,
            message: message,
            exitCode: 0,
            stdout: stdout,
            stderr: stderr,
            verificationStatus: verificationStatus
        )
    }

    private func testSession() -> ObservationSession {
        ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString).sqlite"
            )
    }
}

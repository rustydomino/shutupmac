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
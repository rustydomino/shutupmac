import Foundation
@testable import NotilogCore
import XCTest

final class ActionRunnerTests: XCTestCase {
    func testRunDryRunReturnsDryRunResult() {
        let event = sampleEvent()

        let match = AutomationMatch(
            ruleName: "Test rule",
            action: .exec(
                command: "/usr/bin/true",
                arguments: []
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.runDryRun(match)

        XCTAssertEqual(result.ruleName, "Test rule")
        XCTAssertEqual(result.status, .dryRun)
        XCTAssertEqual(result.message, "would run: /usr/bin/true")
        XCTAssertEqual(result.action.summary, "/usr/bin/true")
        XCTAssertEqual(result.event.notification.app, "Self Service+")
    }

    func testRunDryRunIncludesExecArgumentsInMessage() {
        let event = sampleEvent()

        let match = AutomationMatch(
            ruleName: "Exec with args",
            action: .exec(
                command: "/bin/echo",
                arguments: ["hello", "world"]
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.runDryRun(match)

        XCTAssertEqual(result.message, "would run: /bin/echo hello world")
    }

    func testRunDryRunExpandsExecArguments() {
        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .exec(
                command: "/usr/local/bin/shutupmac-cli",
                arguments: [
                    "dismiss",
                    "--notification-key",
                    "{{notification.key}}"
                ]
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.runDryRun(match)

        XCTAssertEqual(
            result.message,
            "would run: /usr/local/bin/shutupmac-cli dismiss --notification-key AXNotificationCenterAlert|ABC-123"
        )
    }

    func testRunDryRunStoresResolvedExecAction() {
        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .exec(
                command: "/usr/local/bin/shutupmac-cli",
                arguments: [
                    "dismiss",
                    "--notification-key",
                    "{{notification.key}}"
                ]
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.runDryRun(match)

        XCTAssertEqual(
            result.resolvedAction,
            .exec(
                command: "/usr/local/bin/shutupmac-cli",
                arguments: [
                    "dismiss",
                    "--notification-key",
                    "AXNotificationCenterAlert|ABC-123"
                ]
            )
        )
    }

    func testRunExecSucceedsForUsrBinTrue() {
    let event = sampleEvent()

    let match = AutomationMatch(
        ruleName: "True command",
        action: .exec(
            command: "/usr/bin/true",
            arguments: []
        ),
        event: event
    )

    let runner = ActionRunner()
    let result = runner.run(match)

    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.exitCode, Int32(0))
    XCTAssertTrue(result.stdout.isEmpty)
    XCTAssertTrue(result.stderr.isEmpty)
}

func testRunExecFailsForUsrBinFalse() {
    let event = sampleEvent()

    let match = AutomationMatch(
        ruleName: "False command",
        action: .exec(
            command: "/usr/bin/false",
            arguments: []
        ),
        event: event
    )

    let runner = ActionRunner()
    let result = runner.run(match)

    XCTAssertEqual(result.status, .failed)
    XCTAssertEqual(result.exitCode, Int32(1))
}

func testRunExecRefusesNonAbsoluteCommandPath() {
    let event = sampleEvent()

    let match = AutomationMatch(
        ruleName: "Relative command",
        action: .exec(
            command: "echo",
            arguments: ["hello"]
        ),
        event: event
    )

    let runner = ActionRunner()
    let result = runner.run(match)

    XCTAssertEqual(result.status, .failed)
    XCTAssertNil(result.exitCode)
    XCTAssertEqual(
        result.message,
        "refusing to run non-absolute command path: echo"
    )
}

func testRunExecFailsForMissingExecutable() {
    let event = sampleEvent()

    let match = AutomationMatch(
        ruleName: "Missing command",
        action: .exec(
            command: "/not/a/real/command",
            arguments: []
        ),
        event: event
    )

    let runner = ActionRunner()
    let result = runner.run(match)

    XCTAssertEqual(result.status, .failed)
    XCTAssertNil(result.exitCode)
    XCTAssertEqual(
        result.message,
        "command is not executable: /not/a/real/command"
    )
}

func testRunExecCapturesStdout() {
    let event = sampleEvent()

    let match = AutomationMatch(
        ruleName: "Echo command",
        action: .exec(
            command: "/bin/echo",
            arguments: ["hello"]
        ),
        event: event
    )

    let runner = ActionRunner()
    let result = runner.run(match)

    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.exitCode, Int32(0))
    XCTAssertEqual(result.stdout, "hello\n")
    XCTAssertTrue(result.stderr.isEmpty)
}

func testRunExecCapturesStderr() {
    let event = sampleEvent()

    let match = AutomationMatch(
        ruleName: "Stderr command",
        action: .exec(
            command: "/bin/sh",
            arguments: ["-c", "echo error-message 1>&2"]
        ),
        event: event
    )

    let runner = ActionRunner()
    let result = runner.run(match)

    XCTAssertEqual(result.status, .succeeded)
    XCTAssertEqual(result.exitCode, Int32(0))
    XCTAssertTrue(result.stdout.isEmpty)
    XCTAssertEqual(result.stderr, "error-message\n")
}

    func testRunDryRunResolvesShutUpMacNotificationKey() {
        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: "/bin/echo"
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.runDryRun(match)

        XCTAssertEqual(
            result.resolvedAction,
            .shutUpMacDismiss(
                command: "/bin/echo",
                notificationKey: "AXNotificationCenterAlert|ABC-123"
            )
        )
        XCTAssertEqual(
            result.message,
            "would run: ShutUpMac dismiss: /bin/echo --dismiss-key AXNotificationCenterAlert|ABC-123"
        )
    }

    func testRunShutUpMacDismissPassesDismissKeyArgument() {
        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: "/bin/echo"
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.run(match)

        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.exitCode, Int32(0))
        XCTAssertEqual(result.verificationStatus, .pending)
        XCTAssertEqual(
            result.stdout,
            "--dismiss-key AXNotificationCenterAlert|ABC-123\n"
        )
    }

    func testRunShutUpMacDismissUsesInjectedHandler() {
        let notificationKey = "AXNotificationCenterAlert|ABC-123"
        var receivedNotificationKey: String?

        let event = sampleEvent(key: notificationKey)

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: "/usr/bin/false"
            ),
            event: event
        )

        let runner = ActionRunner(
            dismissalHandler: { key in
                receivedNotificationKey = key

                return NotificationDismissalResult(
                    succeeded: true,
                    message: "dismissed in process",
                    exitCode: 0
                )
            }
        )

        let result = runner.run(match)

        XCTAssertEqual(receivedNotificationKey, notificationKey)
        XCTAssertEqual(result.status, .succeeded)
        XCTAssertEqual(result.message, "dismissed in process")
        XCTAssertEqual(result.exitCode, Int32(0))
        XCTAssertEqual(
            result.verificationStatus,
            .probablySucceeded
        )
    }

    func testShutUpMacNoVisibleProgressAwaitsVerification() throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "fake-shutupmac-\(UUID().uuidString).sh"
            )

        let script = """
        #!/bin/sh
        echo "Dismiss action was performed, but no visible progress was observed for key: $2" >&2
        exit 1
        """

        try script.write(
            to: scriptURL,
            atomically: true,
            encoding: .utf8
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )

        defer {
            try? FileManager.default.removeItem(at: scriptURL)
        }

        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: scriptURL.path
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.run(match)

        XCTAssertEqual(result.status, .uncertain)
        XCTAssertEqual(result.exitCode, Int32(1))
        XCTAssertEqual(result.verificationStatus, .pending)
        XCTAssertTrue(
            result.message.contains("awaiting delayed verification")
        )
    }

    func testFailedShutUpMacDismissDoesNotAwaitVerification() {
        let event = sampleEvent(
            key: "AXNotificationCenterAlert|ABC-123"
        )

        let match = AutomationMatch(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: "/usr/bin/false"
            ),
            event: event
        )

        let runner = ActionRunner()
        let result = runner.run(match)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.exitCode, Int32(1))
        XCTAssertNil(result.verificationStatus)
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

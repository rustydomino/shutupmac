import XCTest
@testable import ShutUpMac

final class ShutUpMacTests: XCTestCase {
    func testRepeatedRuleIsIncludedOnlyOnce() throws {
        let ruleID = UUID()

        let matchedRule = MatchedRuleSnapshot(
            id: ruleID,
            name: "Example rule",
            actions: [
                .dismissNotification(
                    command: "shutupmac-cli"
                )
            ]
        )

        let notification = ActivityNotificationSnapshot(
            key: "notification-key",
            app: "Mail",
            title: "New message",
            subtitle: "",
            body: "Hello, world"
        )

        let firstItem = ActivityItem(
            timestamp: Date(),
            kind: .notificationAppeared,
            summary: "Notification appeared",
            notification: notification,
            matchedRules: [matchedRule]
        )

        let repeatedItem = ActivityItem(
            timestamp: Date(),
            kind: .notificationAppeared,
            summary: "Notification appeared again",
            notification: notification,
            matchedRules: [matchedRule]
        )

        var record = try XCTUnwrap(
            NotificationActivityRecord(from: firstItem)
        )

        record.append(repeatedItem)

        XCTAssertEqual(record.matchedRuleCount, 1)
        XCTAssertEqual(record.matchedRules, [matchedRule])
        XCTAssertEqual(
            record.rulesMatchedDisplay,
            "1 rule matched"
        )
    }
    
    func testSameNameRulesWithDifferentIDsRemainDistinct() throws {
        let firstRule = MatchedRuleSnapshot(
            id: UUID(),
            name: "Duplicate name",
            actions: [
                .dismissNotification(
                    command: "shutupmac-cli"
                )
            ]
        )

        let secondRule = MatchedRuleSnapshot(
            id: UUID(),
            name: "Duplicate name",
            actions: [
                .diagnosticLog(
                    message: "Test diagnostic message"
                )
            ]
        )

        let notification = ActivityNotificationSnapshot(
            key: "notification-key",
            app: "Mail",
            title: "New message",
            subtitle: "",
            body: "Hello, world"
        )

        let item = ActivityItem(
            timestamp: Date(),
            kind: .notificationAppeared,
            summary: "Notification appeared",
            notification: notification,
            matchedRules: [
                firstRule,
                secondRule
            ]
        )

        let record = try XCTUnwrap(
            NotificationActivityRecord(from: item)
        )

        XCTAssertEqual(record.matchedRuleCount, 2)
        XCTAssertEqual(record.matchedRules.count, 2)
        XCTAssertTrue(record.matchedRules.contains(firstRule))
        XCTAssertTrue(record.matchedRules.contains(secondRule))
        XCTAssertEqual(
            record.rulesMatchedDisplay,
            "2 rules matched"
        )
    }
    
    func testActionSnapshotsUseExpectedDisplayNames() {
        let dismissAction = MatchedRuleActionSnapshot
            .dismissNotification(
                command: "shutupmac-cli"
            )

        let commandAction = MatchedRuleActionSnapshot
            .runCommand(
                command: "/usr/bin/echo",
                arguments: ["Hello"]
            )

        let diagnosticAction = MatchedRuleActionSnapshot
            .diagnosticLog(
                message: "Test diagnostic message"
            )

        XCTAssertEqual(
            dismissAction.displayName,
            "Dismiss notification"
        )

        XCTAssertEqual(
            commandAction.displayName,
            "Run command or script"
        )

        XCTAssertEqual(
            diagnosticAction.displayName,
            "Diagnostic log"
        )
    }
}

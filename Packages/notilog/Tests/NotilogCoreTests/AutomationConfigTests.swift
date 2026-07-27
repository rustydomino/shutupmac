import XCTest
@testable import NotilogCore

final class AutomationConfigTests: XCTestCase {
    func testDecodesExecRuleConfig() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "name": "Appeared notification probe",
              "enabled": true,
              "match": {
                "eventTypes": ["appeared"]
              },
              "actions": [
                {
                  "type": "exec",
                  "command": "/usr/bin/true",
                  "arguments": [
                    "--notification-key",
                    "{{notification.key}}"
                  ]
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AutomationConfig.self, from: json)
        let rules = try config.notificationRules()

        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(
            rules[0].id,
            UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!
        )
        XCTAssertEqual(rules[0].name, "Appeared notification probe")
        XCTAssertTrue(rules[0].enabled)
        XCTAssertEqual(
            rules[0].actions[0].summary,
            "/usr/bin/true --notification-key {{notification.key}}"
        )

        let event = sampleEvent(type: .appeared)
        XCTAssertTrue(rules[0].matches(event))
    }

    func testDisabledRuleConfigDoesNotMatch() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000002",
              "name": "Disabled rule",
              "enabled": false,
              "match": {
                "eventTypes": ["appeared"]
              },
              "actions": [
                {
                  "type": "exec",
                  "command": "/usr/bin/true"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AutomationConfig.self, from: json)
        let rules = try config.notificationRules()

        XCTAssertEqual(rules.count, 1)
        XCTAssertFalse(rules[0].matches(sampleEvent(type: .appeared)))
    }

    func testDecodesDryRunLogAction() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000003",
              "name": "Log title",
              "match": {
                "eventTypes": ["appeared"]
              },
              "actions": [
                {
                  "type": "dry_run_log",
                  "message": "title={{notification.title}}"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AutomationConfig.self, from: json)
        let rules = try config.notificationRules()

        XCTAssertEqual(rules[0].actions[0].summary, "title={{notification.title}}")
    }

    func testThrowsForUnknownActionType() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000004",
              "name": "Bad action",
              "match": {},
              "actions": [
                {
                  "type": "wat"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AutomationConfig.self, from: json)

        XCTAssertThrowsError(try config.notificationRules()) { error in
            XCTAssertEqual(
                error as? AutomationConfigError,
                .unknownActionType("wat")
            )
        }
    }

    func testThrowsForMissingExecCommand() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000005",  
              "name": "Missing command",
              "match": {},
              "actions": [
                {
                  "type": "exec"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AutomationConfig.self, from: json)

        XCTAssertThrowsError(try config.notificationRules()) { error in
            XCTAssertEqual(
                error as? AutomationConfigError,
                .missingExecCommand
            )
        }
    }

    func testDecodesShutUpMacDismissWithDefaultCommand() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000005",
              "name": "Dismiss notification",
              "match": {
                "eventTypes": ["appeared"]
              },
              "actions": [
                {
                  "type": "shutupmac_dismiss"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(AutomationConfig.self, from: json)
        let rules = try config.notificationRules()

        XCTAssertEqual(
            rules[0].actions[0].summary,
            "ShutUpMac dismiss notification via /Applications/ShutUpMac.app/Contents/Helpers/shutupmac-cli"
        )
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

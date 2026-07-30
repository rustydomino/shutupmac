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

    func testDecodesRuleExceptions() throws {
        let json = """
        {
          "rules": [
            {
              "id": "00000000-0000-0000-0000-000000000006",
              "name": "Dismiss routine Teams messages",
              "enabled": true,
              "match": {
                "eventTypes": ["appeared"],
                "appEquals": "Microsoft Teams",
                "caseSensitive": false
              },
              "exceptions": [
                {
                  "field": "title",
                  "contains": "Mike"
                },
                {
                  "field": "title",
                  "contains": "Alice"
                },
                {
                  "field": "body",
                  "contains": "urgent"
                }
              ],
              "actions": [
                {
                  "type": "shutupmac_dismiss"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(
            AutomationConfig.self,
            from: json
        )

        let rules = try config.notificationRules()
        let rule = try XCTUnwrap(rules.first)

        XCTAssertEqual(rule.exceptions.count, 3)

        XCTAssertEqual(
            rule.exceptions[0],
            NotificationException(
                field: .title,
                searchText: "Mike"
            )
        )

        XCTAssertEqual(
            rule.exceptions[1],
            NotificationException(
                field: .title,
                searchText: "Alice"
            )
        )

        XCTAssertEqual(
            rule.exceptions[2],
            NotificationException(
                field: .body,
                searchText: "urgent"
            )
        )

        XCTAssertFalse(
            rule.matches(
                sampleEvent(
                    app: "Microsoft Teams",
                    title: "Message from Alice"
                )
            )
        )

        XCTAssertFalse(
            rule.matches(
                sampleEvent(
                    app: "Microsoft Teams",
                    title: "Message from Charlie",
                    body: "This is URGENT."
                )
            )
        )

        XCTAssertTrue(
            rule.matches(
                sampleEvent(
                    app: "Microsoft Teams",
                    title: "Message from Charlie",
                    body: "Weekly update"
                )
            )
        )
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

    func testSettingRuleEnabledPreservesRuleConfigurationAndOrder()
        throws {
        let firstID = UUID(
            uuidString:
                "00000000-0000-0000-0000-000000000101"
        )!

        let targetID = UUID(
            uuidString:
                "00000000-0000-0000-0000-000000000102"
        )!

        let json = """
        {
        "rules": [
            {
            "id": "\(firstID.uuidString)",
            "name": "First rule",
            "enabled": true,
            "match": {
                "eventTypes": ["appeared"]
            },
            "actions": [
                {
                "type": "shutupmac_dismiss"
                }
            ]
            },
            {
            "id": "\(targetID.uuidString)",
            "name": "Target rule",
            "enabled": true,
            "match": {
                "eventTypes": ["appeared"],
                "appContains": "Mail",
                "titleContains": "Newsletter",
                "bodyContains": "unsubscribe",
                "caseSensitive": true
            },
            "exceptions": [
                {
                "field": "title",
                "contains": "Important"
                }
            ],
            "actions": [
                {
                "type": "shutupmac_dismiss"
                }
            ]
            }
        ]
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(
            AutomationConfig.self,
            from: json
        )

        let updated = config.settingRuleEnabled(
            id: targetID,
            enabled: false
        )

        XCTAssertEqual(updated.rules.count, 2)
        XCTAssertEqual(updated.rules[0].id, firstID)
        XCTAssertEqual(updated.rules[1].id, targetID)

        XCTAssertEqual(updated.rules[0].enabled, true)

        let rule = updated.rules[1]

        XCTAssertEqual(rule.name, "Target rule")
        XCTAssertEqual(rule.enabled, false)

        XCTAssertEqual(rule.match.eventTypes, [.appeared])
        XCTAssertEqual(rule.match.appContains, "Mail")
        XCTAssertEqual(
            rule.match.titleContains,
            "Newsletter"
        )
        XCTAssertEqual(
            rule.match.bodyContains,
            "unsubscribe"
        )
        XCTAssertEqual(rule.match.caseSensitive, true)

        let exception = try XCTUnwrap(
            rule.exceptions?.first
        )

        XCTAssertEqual(exception.field, .title)
        XCTAssertEqual(exception.contains, "Important")

        XCTAssertEqual(rule.actions.count, 1)
        XCTAssertEqual(
            rule.actions[0].type,
            "shutupmac_dismiss"
        )

        XCTAssertEqual(config.rules[1].enabled, true)
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

import XCTest
import NotilogCore
@testable import ShutUpMac

private final class StubAutomationConfigurationActivator:
    AutomationConfigurationActivating,
    @unchecked Sendable {

    private let result:
        AutomationConfigurationUpdateResult

    init(
        result: AutomationConfigurationUpdateResult
    ) {
        self.result = result
    }

    func replaceAutomationConfiguration(
        _ configuration: AutomationConfig,
        completion: @escaping
            @MainActor @Sendable (
                AutomationConfigurationUpdateResult
            ) -> Void
    ) {
        let result = result

        Task { @MainActor in
            completion(result)
        }
    }
}

final class ShutUpMacTests: XCTestCase {

    func testNotilogRedactionPolicyIsDisabledWhenMasterSettingIsOff() {
        let policy = AppPreferences.makeNotilogRedactionPolicy(
            enabled: false,
            redactTitle: true,
            redactSubtitle: true,
            redactBody: true
        )

        XCTAssertEqual(
            policy,
            .disabled
        )
    }

    func testActivityItemFactoryLeavesContentsUnchangedWhenRedactionDisabled()
        throws {

        let timestamp = Date(
            timeIntervalSince1970: 100
        )

        let sourceEvent = NotificationEvent(
            type: .appeared,
            notification: VisibleNotification(
                key:
                    "AXNotificationCenterAlert"
                    + "|activity-factory-disabled",
                app: "Test App",
                title: "Secret title",
                subtitle: "Secret subtitle",
                body: "Secret body"
            ),
            timestamp: timestamp
        )

        let result = NotificationMonitoringResult(
            completedActionVerifications: [],
            recoveredEvents: [],
            events: [
                CoordinatedNotificationEvent(
                    event: sourceEvent,
                    matchedRules: [],
                    actionResults: []
                )
            ]
        )

        let items = ActivityItemFactory.makeItems(
            from: result,
            verificationTimestamp: Date(
                timeIntervalSince1970: 200
            ),
            redactionPolicy: .disabled
        )

        XCTAssertEqual(items.count, 1)

        let item = try XCTUnwrap(items.first)
        let notification = try XCTUnwrap(
            item.notification
        )

        XCTAssertEqual(item.timestamp, timestamp)
        XCTAssertEqual(
            item.kind.rawValue,
            "notificationAppeared"
        )
        XCTAssertEqual(
            item.summary,
            "Appeared — Test App: Secret title"
        )

        XCTAssertEqual(
            notification.key,
            sourceEvent.notification.key
        )
        XCTAssertEqual(notification.app, "Test App")
        XCTAssertEqual(notification.title, "Secret title")
        XCTAssertEqual(
            notification.subtitle,
            "Secret subtitle"
        )
        XCTAssertEqual(notification.body, "Secret body")

        XCTAssertEqual(
            sourceEvent.notification.title,
            "Secret title"
        )
        XCTAssertEqual(
            sourceEvent.notification.subtitle,
            "Secret subtitle"
        )
        XCTAssertEqual(
            sourceEvent.notification.body,
            "Secret body"
        )
    }

    func testActivityItemFactoryAppliesSelectedRedactionFields()
        throws {

        let timestamp = Date(
            timeIntervalSince1970: 300
        )

        let sourceEvent = NotificationEvent(
            type: .appeared,
            notification: VisibleNotification(
                key:
                    "AXNotificationCenterAlert"
                    + "|activity-factory-redacted",
                app: "Test App",
                title: "Secret title",
                subtitle: "Visible subtitle",
                body: "Secret body"
            ),
            timestamp: timestamp
        )

        let result = NotificationMonitoringResult(
            completedActionVerifications: [],
            recoveredEvents: [],
            events: [
                CoordinatedNotificationEvent(
                    event: sourceEvent,
                    matchedRules: [],
                    actionResults: []
                )
            ]
        )

        let items = ActivityItemFactory.makeItems(
            from: result,
            verificationTimestamp: Date(
                timeIntervalSince1970: 400
            ),
            redactionPolicy: RedactionPolicy(
                fields: [
                    .title,
                    .body
                ]
            )
        )

        XCTAssertEqual(items.count, 1)

        let item = try XCTUnwrap(items.first)
        let notification = try XCTUnwrap(
            item.notification
        )

        XCTAssertEqual(item.timestamp, timestamp)
        XCTAssertEqual(
            item.kind.rawValue,
            "notificationAppeared"
        )
        XCTAssertEqual(
            item.summary,
            "Appeared — Test App: [REDACTED]"
        )

        XCTAssertEqual(notification.app, "Test App")
        XCTAssertEqual(notification.title, "[REDACTED]")
        XCTAssertEqual(
            notification.subtitle,
            "Visible subtitle"
        )
        XCTAssertEqual(notification.body, "[REDACTED]")

        XCTAssertEqual(
            sourceEvent.notification.app,
            "Test App"
        )
        XCTAssertEqual(
            sourceEvent.notification.title,
            "Secret title"
        )
        XCTAssertEqual(
            sourceEvent.notification.subtitle,
            "Visible subtitle"
        )
        XCTAssertEqual(
            sourceEvent.notification.body,
            "Secret body"
        )
    }

    func testNotilogRedactionPolicyMapsSelectedContentFields() {
        let cases: [
            (
                name: String,
                redactTitle: Bool,
                redactSubtitle: Bool,
                redactBody: Bool,
                expectedFields: Set<RedactionField>
            )
        ] = [
            (
                name: "title only",
                redactTitle: true,
                redactSubtitle: false,
                redactBody: false,
                expectedFields: [.title]
            ),
            (
                name: "subtitle only",
                redactTitle: false,
                redactSubtitle: true,
                redactBody: false,
                expectedFields: [.subtitle]
            ),
            (
                name: "body only",
                redactTitle: false,
                redactSubtitle: false,
                redactBody: true,
                expectedFields: [.body]
            ),
            (
                name: "all GUI fields",
                redactTitle: true,
                redactSubtitle: true,
                redactBody: true,
                expectedFields: [
                    .title,
                    .subtitle,
                    .body
                ]
            )
        ]

        for testCase in cases {
            let policy = AppPreferences.makeNotilogRedactionPolicy(
                enabled: true,
                redactTitle: testCase.redactTitle,
                redactSubtitle: testCase.redactSubtitle,
                redactBody: testCase.redactBody
            )

            XCTAssertEqual(
                policy,
                RedactionPolicy(
                    fields: testCase.expectedFields
                ),
                testCase.name
            )

            XCTAssertFalse(
                policy.redacts(.app),
                "\(testCase.name) unexpectedly redacts app"
            )

            XCTAssertFalse(
                policy.redacts(.attachments),
                "\(testCase.name) unexpectedly redacts attachments"
            )
        }
    }

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
    
    func testDisplayTitleIsHiddenWhenItMatchesAppName() throws {
        let notification = ActivityNotificationSnapshot(
            key: "notification-key",
            app: "Mail",
            title: "  mail  ",
            subtitle: "Inbox",
            body: "New message"
        )

        let item = ActivityItem(
            timestamp: Date(),
            kind: .notificationAppeared,
            summary: "Notification appeared",
            notification: notification,
            matchedRules: []
        )

        let record = try XCTUnwrap(
            NotificationActivityRecord(from: item)
        )

        XCTAssertNil(record.displayTitle)
        XCTAssertEqual(record.displaySubtitle, "Inbox")
    }
    
    func testBlankDisplayFieldsAreOmitted() throws {
        let notification = ActivityNotificationSnapshot(
            key: "notification-key",
            app: "Mail",
            title: "   ",
            subtitle: "\n\t",
            body: "New message"
        )

        let item = ActivityItem(
            timestamp: Date(),
            kind: .notificationAppeared,
            summary: "Notification appeared",
            notification: notification,
            matchedRules: []
        )

        let record = try XCTUnwrap(
            NotificationActivityRecord(from: item)
        )

        XCTAssertNil(record.displayTitle)
        XCTAssertNil(record.displaySubtitle)
        XCTAssertEqual(record.body, "New message")
    }
    
    func testRecordedZeroMatchesDisplaysDash() throws {
        let notification = ActivityNotificationSnapshot(
            key: "notification-key",
            app: "Mail",
            title: "New message",
            subtitle: "",
            body: "Hello"
        )

        let item = ActivityItem(
            timestamp: Date(),
            kind: .notificationAppeared,
            summary: "Notification appeared",
            notification: notification,
            matchedRules: []
        )

        let record = try XCTUnwrap(
            NotificationActivityRecord(from: item)
        )

        XCTAssertEqual(record.rulesMatchedDisplay, "—")
    }
    
    func testLiveAppearanceReplacesNotRecordedRuleState() {
        let notification = ActivityNotificationSnapshot(
            key: "notification-key",
            app: "Mail",
            title: "Historical message",
            subtitle: "",
            body: "Hello"
        )

        var record = NotificationActivityRecord(
            historicalNotification: notification,
            appearedAt: Date(timeIntervalSince1970: 100)
        )

        XCTAssertEqual(
            record.rulesMatchedDisplay,
            "Not recorded"
        )

        let liveItem = ActivityItem(
            timestamp: Date(timeIntervalSince1970: 200),
            kind: .notificationAppeared,
            summary: "Notification appeared",
            notification: notification,
            matchedRules: []
        )

        record.append(liveItem)

        XCTAssertEqual(
            record.rulesMatchedDisplay,
            "—"
        )
    }
    
    @MainActor
    func testLoadingHistoricalRecordsKeepsNewestOneThousand() {
        let records = (1...1_001).map { index in
            let notification = ActivityNotificationSnapshot(
                key: "notification-\(index)",
                app: "Test App",
                title: "Notification \(index)",
                subtitle: "",
                body: "Body \(index)"
            )

            return NotificationActivityRecord(
                historicalNotification: notification,
                appearedAt: Date(
                    timeIntervalSince1970:
                        TimeInterval(index)
                )
            )
        }

        let store = ActivityStore()

        store.loadHistoricalRecords(records)

        XCTAssertEqual(store.records.count, 1_000)
        XCTAssertTrue(store.isAtRecordCapacity)
        XCTAssertEqual(
            store.records.first?.id,
            "notification-2"
        )
        XCTAssertEqual(
            store.records.last?.id,
            "notification-1001"
        )
        XCTAssertTrue(
            store.records.allSatisfy {
                $0.rulesMatchedDisplay == "Not recorded"
            }
        )
    }
    
    @MainActor
    func testActivityStoreBelowCapacityIsNotAtCapacity() {
        let notification = ActivityNotificationSnapshot(
            key: "notification-1",
            app: "Test App",
            title: "Test",
            subtitle: "",
            body: "Body"
        )

        let record = NotificationActivityRecord(
            historicalNotification: notification,
            appearedAt: Date()
        )

        let store = ActivityStore()
        store.loadHistoricalRecords([record])

        XCTAssertFalse(store.isAtRecordCapacity)
    }

    @MainActor
    func testConfigurationStorePreservesValidConfigurationAfterFailedReload()
        throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        let validConfiguration = AutomationConfig(
            rules: []
        )

        let validData = try JSONEncoder().encode(
            validConfiguration
        )

        try validData.write(
            to: configURL,
            options: .atomic
        )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        let firstLoad = store.load()

        XCTAssertNotNil(firstLoad)
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )
        XCTAssertNil(store.errorMessage)

        try Data(
            "{ invalid json".utf8
        ).write(
            to: configURL,
            options: .atomic
        )

        let failedReload = store.load()

        XCTAssertNil(failedReload)

        // The last successfully loaded configuration remains available.
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )

        XCTAssertNotNil(store.errorMessage)
    }
    
    @MainActor
    func testConfigurationStoreUsesEmptyConfigurationWhenFileIsMissing()
        throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: configURL.path
            )
        )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        let configuration = store.load()

        XCTAssertNotNil(configuration)
        XCTAssertEqual(
            configuration?.rules.count,
            0
        )
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )
        XCTAssertNil(store.errorMessage)

        // Loading an absent configuration should not create a file.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: configURL.path
            )
        )
    }
    
    @MainActor
    func testConfigurationStoreWritesConfigurationWithoutActivatingIt()
        throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        XCTAssertNil(store.configuration)

        let candidate = AutomationConfig(
            rules: []
        )

        try store.writeConfiguration(
            candidate
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: configURL.path
            )
        )

        let writtenConfiguration =
            try AutomationConfig.load(
                from: configURL
            )

        XCTAssertEqual(
            writtenConfiguration.rules.count,
            0
        )

        // Writing alone does not mean the runtime accepted
        // and activated this configuration.
        XCTAssertNil(store.configuration)
    }
    
    @MainActor
    func testConfigurationStoreDoesNotOverwriteFileWithInvalidConfiguration()
        throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        let originalConfiguration =
            AutomationConfig(rules: [])

        let encoder = JSONEncoder()

        try encoder.encode(
            originalConfiguration
        ).write(
            to: configURL,
            options: .atomic
        )

        let invalidConfigurationData = Data(
            """
            {
              "rules": [
                {
                  "id": "605121D1-2640-43A8-BC38-659A79DC18C6",
                  "name": "Invalid exec rule",
                  "enabled": true,
                  "match": {
                    "eventTypes": [
                      "appeared"
                    ],
                    "appEquals": "Messages",
                    "caseSensitive": false
                  },
                  "actions": [
                    {
                      "type": "exec"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

            let invalidConfiguration =
                try JSONDecoder().decode(
                    AutomationConfig.self,
                    from: invalidConfigurationData
                )
            
        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        XCTAssertThrowsError(
            try store.writeConfiguration(
                invalidConfiguration
            )
        )

        let configurationAfterFailure =
            try AutomationConfig.load(
                from: configURL
            )

        XCTAssertEqual(
            configurationAfterFailure.rules.count,
            0
        )
    }

    @MainActor
    func testSaveAndActivateRestoresPreviousFileWhenActivationFails()
        async throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        // Use deliberately compact JSON so that we can prove
        // rollback restores the exact previous bytes.
        let originalData = Data(
            #"{"rules":[]}"#.utf8
        )

        try originalData.write(
            to: configURL,
            options: .atomic
        )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        XCTAssertNotNil(store.load())
        XCTAssertNil(store.errorMessage)

        let controller = NotilogMonitoringController(
            onHistoricalRecords: { _ in },
            onActivityItems: { _ in }
        )

        // The controller has deliberately not been started,
        // so runtime activation must fail.
        store.saveAndActivate(
            AutomationConfig(rules: []),
            using: controller
        )

        // Replacement is dispatched through the controller queue,
        // then its result is returned to the main actor.
        for _ in 0..<100 {
            if store.errorMessage != nil {
                break
            }

            try await Task.sleep(
                nanoseconds: 10_000_000
            )
        }

        XCTAssertNotNil(store.errorMessage)

        let restoredData = try Data(
            contentsOf: configURL
        )

        XCTAssertEqual(
            restoredData,
            originalData
        )

        // Failed activation must retain the previously active
        // in-memory configuration.
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )
    }
    
    @MainActor
    func testSaveAndActivatePublishesConfigurationAfterActivationSucceeds()
        async throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: configURL.path
            )
        )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        XCTAssertNil(store.configuration)

        let activator =
            StubAutomationConfigurationActivator(
                result: .activated
            )

        store.saveAndActivate(
            AutomationConfig(rules: []),
            using: activator
        )

        for _ in 0..<100 {
            if store.configuration != nil
                || store.errorMessage != nil {
                break
            }

            try await Task.sleep(
                nanoseconds: 10_000_000
            )
        }

        XCTAssertNil(store.errorMessage)
        XCTAssertNotNil(store.configuration)

        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: configURL.path
            )
        )

        let writtenConfiguration =
            try AutomationConfig.load(
                from: configURL
            )

        XCTAssertEqual(
            writtenConfiguration.rules.count,
            0
        )
    }
    
    @MainActor
    func testReloadFromDiskActivatesValidExternalConfiguration()
        async throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        let originalConfiguration =
            AutomationConfig(rules: [])

        try JSONEncoder().encode(
            originalConfiguration
        ).write(
            to: configURL,
            options: .atomic
        )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        XCTAssertNotNil(store.load())
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )

        let externallyEditedData = Data(
            """
            {
              "rules": [
                {
                  "id": "0C395504-6752-4464-B3B2-2DB117B62466",
                  "name": "Reloaded Mail rule",
                  "enabled": true,
                  "match": {
                    "eventTypes": [
                      "appeared"
                    ],
                    "appEquals": "Mail",
                    "caseSensitive": false
                  },
                  "actions": [
                    {
                      "type": "dry_run_log",
                      "message": "Mail matched"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        try externallyEditedData.write(
            to: configURL,
            options: .atomic
        )

        let activator =
            StubAutomationConfigurationActivator(
                result: .activated
            )

        store.reloadFromDisk(
            using: activator
        )

        for _ in 0..<100 {
            if store.configuration?.rules.count == 1
                || store.errorMessage != nil {
                break
            }

            try await Task.sleep(
                nanoseconds: 10_000_000
            )
        }

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(
            store.configuration?.rules.count,
            1
        )

        XCTAssertEqual(
            store.configuration?.rules.first?.name,
            "Reloaded Mail rule"
        )
    }
    
    @MainActor
    func testReloadFromDiskPreservesActiveConfigurationWhenExternalFileIsInvalid()
        async throws {

        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let configURL =
            directoryURL.appendingPathComponent(
                "config.json"
            )

        let originalConfiguration =
            AutomationConfig(rules: [])

        try JSONEncoder().encode(
            originalConfiguration
        ).write(
            to: configURL,
            options: .atomic
        )

        let store = AutomationConfigurationStore(
            configURL: configURL
        )

        XCTAssertNotNil(store.load())
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )
        XCTAssertNil(store.errorMessage)

        let invalidExternalData = Data(
            """
            {
              "rules": [
                {
                  "id": "DC710954-BDC6-4034-975F-E21B5DD97249",
                  "name": "Invalid external rule",
                  "enabled": true,
                  "match": {
                    "eventTypes": [
                      "appeared"
                    ],
                    "appEquals": "Mail",
                    "caseSensitive": false
                  },
                  "actions": [
                    {
                      "type": "exec"
                    }
                  ]
                }
              ]
            }
            """.utf8
        )

        try invalidExternalData.write(
            to: configURL,
            options: .atomic
        )

        let activator =
            StubAutomationConfigurationActivator(
                result: .activated
            )

        store.reloadFromDisk(
            using: activator
        )

        XCTAssertNotNil(store.errorMessage)

        // The previously active configuration remains published.
        XCTAssertEqual(
            store.configuration?.rules.count,
            0
        )
    }
    
    func testMonitoringRuntimeCanToggleDatabaseLogging()
        throws {

        let temporaryRoot =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        defer {
            try? FileManager.default.removeItem(
                at: temporaryRoot
            )
        }

        let runtimePaths = NotilogRuntimePaths(
            applicationSupport: temporaryRoot
        )

        let runtime = try NotilogMonitoringRuntime(
            runtimePaths: runtimePaths,
            initialConfiguration:
                AutomationConfig(rules: []),
            loggingEnabled: false
        )

        // Starting with logging disabled must not create
        // a new database merely for history.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: runtimePaths.database.path
            )
        )

        try runtime.setLoggingEnabled(true)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: runtimePaths.database.path
            )
        )

        try runtime.setLoggingEnabled(false)

        // Disabling logging retains the database on disk.
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: runtimePaths.database.path
            )
        )
    }

    func testMonitoringRuntimeKeepsExistingHistoryReadableWhenLoggingIsDisabled()
        throws {

        let temporaryRoot =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        defer {
            try? FileManager.default.removeItem(
                at: temporaryRoot
            )
        }

        let runtimePaths = NotilogRuntimePaths(
            applicationSupport: temporaryRoot
        )

        try runtimePaths.ensureDirectoriesExist()

        let historicalEvent = NotificationEvent(
            type: .appeared,
            notification: VisibleNotification(
                key: "test-notification",
                app: "Test App",
                title: "Existing history",
                subtitle: "",
                body: "Persisted before logging was disabled"
            ),
            timestamp: Date(
                timeIntervalSince1970: 100
            )
        )

        do {
            let store = try NotificationStore(
                path: runtimePaths.database.path
            )

            let session = ObservationSession(
                id: "historical-session",
                startedAt: Date(
                    timeIntervalSince1970: 90
                )
            )

            try store.startSession(session)

            try store.insert(
                historicalEvent,
                session: session
            )

            try store.endSession(
                session,
                endedAt: Date(
                    timeIntervalSince1970: 110
                )
            )
        }

        let runtime = try NotilogMonitoringRuntime(
            runtimePaths: runtimePaths,
            initialConfiguration:
                AutomationConfig(rules: []),
            loggingEnabled: false
        )

        let historyWhileDisabled =
            try runtime.recentAppearanceEvents()

        XCTAssertEqual(
            historyWhileDisabled.count,
            1
        )

        XCTAssertEqual(
            historyWhileDisabled.first?
                .event.notification.title,
            "Existing history"
        )

        try runtime.setLoggingEnabled(true)
        try runtime.setLoggingEnabled(false)

        let historyAfterToggle =
            try runtime.recentAppearanceEvents()

        XCTAssertEqual(
            historyAfterToggle.count,
            1
        )

        XCTAssertEqual(
            historyAfterToggle.first?
                .event.notification.title,
            "Existing history"
        )
    }
    
}

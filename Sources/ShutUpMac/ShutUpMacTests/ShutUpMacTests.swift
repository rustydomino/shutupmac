import XCTest
import NotilogCore
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

}

import Foundation
@testable import NotilogCore
import XCTest

final class NotificationStoreTests: XCTestCase {
    func testActionVerificationStatusRoundTripsThroughSQLite() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notilog-\(UUID().uuidString).sqlite")

        defer {
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let store = try NotificationStore(path: databaseURL.path)
        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let notification = VisibleNotification(
            key: "AXNotificationCenterAlert|ABC-123",
            app: "Notigen",
            title: "Test notification",
            subtitle: "",
            body: "Testing ShutUpMac verification."
        )

        let event = NotificationEvent(
            type: .appeared,
            notification: notification,
            timestamp: Date(timeIntervalSince1970: 2)
        )

        let result = ActionRunResult(
            ruleName: "Dismiss notification",
            action: .shutUpMacDismiss(
                command: "/usr/bin/true"
            ),
            resolvedAction: .shutUpMacDismiss(
                command: "/usr/bin/true",
                notificationKey: notification.key
            ),
            event: event,
            status: .succeeded,
            message: "ShutUpMac accepted dismissal request",
            exitCode: 0,
            verificationStatus: .pending
        )

        let actionRunID = try store.insert(
            result,
            session: session
        )

        let records = try store.recentActionRuns(limit: 10)

        XCTAssertEqual(records.count, 1)

        let record = try XCTUnwrap(records.first)

        XCTAssertGreaterThan(actionRunID, 0)
        XCTAssertEqual(record.id, actionRunID)
        XCTAssertEqual(record.status, .succeeded)

        XCTAssertEqual(record.verificationStatus, .pending)
        XCTAssertEqual(record.message, "ShutUpMac accepted dismissal request")
        XCTAssertEqual(record.exitCode, 0)
        XCTAssertEqual(
            record.notification.key,
            "AXNotificationCenterAlert|ABC-123"
        )

        try store.updateActionVerificationStatus(
            .probablySucceeded,
            forActionRunID: actionRunID
        )

        let updatedRecords = try store.recentActionRuns(limit: 10)
        let updatedRecord = try XCTUnwrap(updatedRecords.first)

        XCTAssertEqual(updatedRecord.id, actionRunID)
        XCTAssertEqual(
            updatedRecord.verificationStatus,
            .probablySucceeded
        )
    }

    func testRecentAppearanceEventsReturnsNewestAppearancesOldestFirst() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString).sqlite"
            )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let firstNotification = VisibleNotification(
            key: "notification-1",
            app: "Mail",
            title: "First",
            subtitle: "",
            body: "First notification"
        )

        let secondNotification = VisibleNotification(
            key: "notification-2",
            app: "Messages",
            title: "Second",
            subtitle: "",
            body: "Second notification"
        )

        let thirdNotification = VisibleNotification(
            key: "notification-3",
            app: "Calendar",
            title: "Third",
            subtitle: "",
            body: "Third notification"
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: firstNotification,
                timestamp: Date(timeIntervalSince1970: 10)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .disappeared,
                notification: firstNotification,
                timestamp: Date(timeIntervalSince1970: 20)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: secondNotification,
                timestamp: Date(timeIntervalSince1970: 30)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .disappeared,
                notification: secondNotification,
                timestamp: Date(timeIntervalSince1970: 40)
            ),
            session: session
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: thirdNotification,
                timestamp: Date(timeIntervalSince1970: 50)
            ),
            session: session
        )

        let records = try store.recentAppearanceEvents(
            limit: 2
        )

        XCTAssertEqual(records.count, 2)

        XCTAssertEqual(
            records.map(\.event.notification.key),
            [
                "notification-2",
                "notification-3",
            ]
        )

        XCTAssertTrue(
            records.allSatisfy {
                $0.event.type == .appeared
            }
        )
    }

    func testRecentAppearanceEventsCapsResultAtOneThousand() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-\(UUID().uuidString).sqlite"
            )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        for index in 1 ... 1001 {
            let notification = VisibleNotification(
                key: "notification-\(index)",
                app: "Test App",
                title: "Notification \(index)",
                subtitle: "",
                body: "Body \(index)"
            )

            try store.insert(
                NotificationEvent(
                    type: .appeared,
                    notification: notification,
                    timestamp: Date(
                        timeIntervalSince1970:
                        TimeInterval(index)
                    )
                ),
                session: session
            )
        }

        let records = try store.recentAppearanceEvents(
            limit: 50000
        )

        XCTAssertEqual(records.count, 1000)

        XCTAssertEqual(
            records.first?.event.notification.key,
            "notification-2"
        )

        XCTAssertEqual(
            records.last?.event.notification.key,
            "notification-1001"
        )
    }

    func testNotificationHistoryTruncatesFreeFormTextButPreservesActiveNotification()
        throws
    {
        let databaseURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-\(UUID().uuidString).sqlite"
                )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let longApp = String(
            repeating: "A",
            count: 4100
        )

        let longTitle = String(
            repeating: "T",
            count: 4100
        )

        let longSubtitle = String(
            repeating: "S",
            count: 4100
        )

        let longBody = String(
            repeating: "B",
            count: 4100
        )

        let notification = VisibleNotification(
            key: "notification-key",
            app: longApp,
            title: longTitle,
            subtitle: longSubtitle,
            body: longBody
        )

        try store.insert(
            NotificationEvent(
                type: .appeared,
                notification: notification,
                timestamp: Date(
                    timeIntervalSince1970: 2
                )
            ),
            session: session
        )

        let historicalRecord = try XCTUnwrap(
            store.recentEvents(limit: 1).first
        )

        let historicalNotification =
            historicalRecord.event.notification

        XCTAssertEqual(
            historicalNotification.app,
            String(longApp.prefix(4096))
        )

        XCTAssertEqual(
            historicalNotification.title,
            String(longTitle.prefix(4096))
        )

        XCTAssertEqual(
            historicalNotification.subtitle,
            String(longSubtitle.prefix(4096))
        )

        XCTAssertEqual(
            historicalNotification.body,
            String(longBody.prefix(4096))
        )

        XCTAssertEqual(
            historicalNotification.key,
            notification.key
        )

        let activeNotification = try XCTUnwrap(
            store.loadActiveNotifications().first
        )

        XCTAssertEqual(activeNotification.app, longApp)
        XCTAssertEqual(activeNotification.title, longTitle)
        XCTAssertEqual(
            activeNotification.subtitle,
            longSubtitle
        )
        XCTAssertEqual(activeNotification.body, longBody)
        XCTAssertEqual(
            activeNotification.key,
            notification.key
        )
    }

    func testActionHistoryTruncatesFreeFormTextButPreservesIdentity()
        throws
    {
        let databaseURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-\(UUID().uuidString).sqlite"
                )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        let longRuleName = String(
            repeating: "R",
            count: 4100
        )

        let longActionSummary = String(
            repeating: "A",
            count: 4100
        )

        let longResolvedActionSummary = String(
            repeating: "Z",
            count: 4100
        )

        let longMessage = String(
            repeating: "M",
            count: 4100
        )

        let longStandardOutput = String(
            repeating: "O",
            count: 4100
        )

        let longStandardError = String(
            repeating: "E",
            count: 4100
        )

        let notification = VisibleNotification(
            key: "notification-key",
            app: String(repeating: "P", count: 4100),
            title: String(repeating: "T", count: 4100),
            subtitle: String(repeating: "S", count: 4100),
            body: String(repeating: "B", count: 4100)
        )

        let event = NotificationEvent(
            type: .appeared,
            notification: notification,
            timestamp: Date(timeIntervalSince1970: 2)
        )

        let result = ActionRunResult(
            ruleName: longRuleName,
            action: .dryRunLog(
                message: longActionSummary
            ),
            resolvedAction: .dryRunLog(
                message: longResolvedActionSummary
            ),
            event: event,
            status: .succeeded,
            message: longMessage,
            exitCode: 0,
            stdout: longStandardOutput,
            stderr: longStandardError
        )

        try store.insert(
            result,
            session: session
        )

        let record = try XCTUnwrap(
            store.recentActionRuns(limit: 1).first
        )

        XCTAssertEqual(
            record.ruleName,
            String(longRuleName.prefix(4096))
        )

        XCTAssertEqual(
            record.actionSummary,
            String(longActionSummary.prefix(4096))
        )

        XCTAssertEqual(
            record.resolvedActionSummary,
            String(
                longResolvedActionSummary.prefix(4096)
            )
        )

        XCTAssertEqual(
            record.message,
            String(longMessage.prefix(4096))
        )

        XCTAssertEqual(
            record.stdout,
            String(longStandardOutput.prefix(4096))
        )

        XCTAssertEqual(
            record.stderr,
            String(longStandardError.prefix(4096))
        )

        XCTAssertEqual(
            record.notification.app,
            String(notification.app.prefix(4096))
        )

        XCTAssertEqual(
            record.notification.title,
            String(notification.title.prefix(4096))
        )

        XCTAssertEqual(
            record.notification.subtitle,
            String(notification.subtitle.prefix(4096))
        )

        XCTAssertEqual(
            record.notification.body,
            String(notification.body.prefix(4096))
        )

        XCTAssertEqual(
            record.notification.key,
            notification.key
        )
    }

    func testNotificationEventRetentionKeepsNewestRows()
        throws
    {
        let databaseURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-\(UUID().uuidString).sqlite"
                )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path,
            notificationEventLimit: 3,
            actionRunLimit: 10
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        for index in 1...5 {
            let notification = VisibleNotification(
                key: "notification-\(index)",
                app: "Test App",
                title: "Notification \(index)",
                subtitle: "",
                body: "Body \(index)"
            )

            try store.insert(
                NotificationEvent(
                    type: .appeared,
                    notification: notification,
                    timestamp: Date(
                        timeIntervalSince1970:
                            TimeInterval(index)
                    )
                ),
                session: session
            )
        }

        let records = try store.recentEvents(
            limit: 10
        )

        XCTAssertEqual(records.count, 3)

        XCTAssertEqual(
            records.map(\.event.notification.key),
            [
                "notification-3",
                "notification-4",
                "notification-5",
            ]
        )

        let activeNotifications =
            try store.loadActiveNotifications()

        XCTAssertEqual(
            Set(activeNotifications.map(\.key)),
            Set(
                [
                    "notification-1",
                    "notification-2",
                    "notification-3",
                    "notification-4",
                    "notification-5",
                ]
            )
        )
    }

    func testActionRunRetentionKeepsNewestRows()
        throws
    {
        let databaseURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-\(UUID().uuidString).sqlite"
                )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path,
            notificationEventLimit: 10,
            actionRunLimit: 2
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        for index in 1...4 {
            let notification = VisibleNotification(
                key: "notification-\(index)",
                app: "Test App",
                title: "Notification \(index)",
                subtitle: "",
                body: "Body \(index)"
            )

            let event = NotificationEvent(
                type: .appeared,
                notification: notification,
                timestamp: Date(
                    timeIntervalSince1970:
                        TimeInterval(index)
                )
            )

            let result = ActionRunResult(
                ruleName: "Rule \(index)",
                action: .dryRunLog(
                    message: "Action \(index)"
                ),
                resolvedAction: .dryRunLog(
                    message: "Resolved action \(index)"
                ),
                event: event,
                status: .succeeded,
                message: "Result \(index)",
                exitCode: 0,
                stdout: "",
                stderr: ""
            )

            try store.insert(
                result,
                session: session
            )
        }

        let records = try store.recentActionRuns(
            limit: 10
        )

        XCTAssertEqual(records.count, 2)

        XCTAssertEqual(
            records.map(\.ruleName),
            [
                "Rule 3",
                "Rule 4",
            ]
        )

        XCTAssertEqual(
            records.map(\.notification.key),
            [
                "notification-3",
                "notification-4",
            ]
        )
    }
    func testOpeningStorePrunesExistingHistoryToConfiguredLimits()
        throws
    {
        let databaseURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-\(UUID().uuidString).sqlite"
                )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        do {
            let store = try NotificationStore(
                path: databaseURL.path,
                notificationEventLimit: 10,
                actionRunLimit: 10
            )

            for index in 1...5 {
                let notification = VisibleNotification(
                    key: "notification-\(index)",
                    app: "Test App",
                    title: "Notification \(index)",
                    subtitle: "",
                    body: "Body \(index)"
                )

                let event = NotificationEvent(
                    type: .appeared,
                    notification: notification,
                    timestamp: Date(
                        timeIntervalSince1970:
                            TimeInterval(index)
                    )
                )

                try store.insert(
                    event,
                    session: session
                )

                if index <= 4 {
                    let result = ActionRunResult(
                        ruleName: "Rule \(index)",
                        action: .dryRunLog(
                            message: "Action \(index)"
                        ),
                        resolvedAction: .dryRunLog(
                            message: "Resolved action \(index)"
                        ),
                        event: event,
                        status: .succeeded,
                        message: "Result \(index)",
                        exitCode: 0,
                        stdout: "",
                        stderr: ""
                    )

                    try store.insert(
                        result,
                        session: session
                    )
                }
            }
        }

        do {
            let store = try NotificationStore(
                path: databaseURL.path,
                notificationEventLimit: 3,
                actionRunLimit: 2
            )

            let events = try store.recentEvents(
                limit: 10
            )

            XCTAssertEqual(
                events.map(\.event.notification.key),
                [
                    "notification-3",
                    "notification-4",
                    "notification-5",
                ]
            )

            let actionRuns = try store.recentActionRuns(
                limit: 10
            )

            XCTAssertEqual(
                actionRuns.map(\.ruleName),
                [
                    "Rule 3",
                    "Rule 4",
                ]
            )

            let activeNotifications =
                try store.loadActiveNotifications()

            XCTAssertEqual(
                activeNotifications.count,
                5
            )
        }
    }

    func testUpdatingRetentionLimitsPrunesExistingHistory()
        throws
    {
        let databaseURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-\(UUID().uuidString).sqlite"
                )

        defer {
            try? FileManager.default.removeItem(
                at: databaseURL
            )
        }

        let store = try NotificationStore(
            path: databaseURL.path,
            notificationEventLimit: 10,
            actionRunLimit: 10
        )

        let session = ObservationSession(
            id: "test-session",
            startedAt: Date(timeIntervalSince1970: 1)
        )

        for index in 1...5 {
            let notification = VisibleNotification(
                key: "notification-\(index)",
                app: "Test App",
                title: "Notification \(index)",
                subtitle: "",
                body: "Body \(index)"
            )

            let event = NotificationEvent(
                type: .appeared,
                notification: notification,
                timestamp: Date(
                    timeIntervalSince1970:
                        TimeInterval(index)
                )
            )

            try store.insert(
                event,
                session: session
            )

            if index <= 4 {
                let result = ActionRunResult(
                    ruleName: "Rule \(index)",
                    action: .dryRunLog(
                        message: "Action \(index)"
                    ),
                    resolvedAction: .dryRunLog(
                        message: "Resolved action \(index)"
                    ),
                    event: event,
                    status: .succeeded,
                    message: "Result \(index)",
                    exitCode: 0,
                    stdout: "",
                    stderr: ""
                )

                try store.insert(
                    result,
                    session: session
                )
            }
        }

        try store.updateRetentionLimits(
            notificationEventLimit: 3,
            actionRunLimit: 2
        )

        let events = try store.recentEvents(
            limit: 10
        )

        XCTAssertEqual(
            events.map(\.event.notification.key),
            [
                "notification-3",
                "notification-4",
                "notification-5",
            ]
        )

        let actionRuns = try store.recentActionRuns(
            limit: 10
        )

        XCTAssertEqual(
            actionRuns.map(\.ruleName),
            [
                "Rule 3",
                "Rule 4",
            ]
        )

        let statistics = try store.statistics()

        XCTAssertEqual(
            statistics.notificationEventCount,
            3
        )
        XCTAssertEqual(
            statistics.actionRunCount,
            2
        )
        XCTAssertEqual(
            statistics.notificationEventLimit,
            3
        )
        XCTAssertEqual(
            statistics.actionRunLimit,
            2
        )
    }

}

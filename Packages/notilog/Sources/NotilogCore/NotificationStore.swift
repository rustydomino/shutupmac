import Foundation
import SQLite3

public struct NotificationStoreStatistics:
    Equatable,
    Sendable
{
    public let notificationEventCount: Int
    public let actionRunCount: Int
    public let activeNotificationCount: Int
    public let watchSessionCount: Int

    public let oldestNotificationEventDate: Date?
    public let newestNotificationEventDate: Date?
    public let databaseStorageByteCount: Int64

    public let notificationEventLimit: Int
    public let actionRunLimit: Int
}

public enum NotificationStoreAccessMode:
    Equatable,
    Sendable
{
    case readWrite
    case readOnly
}

public final class NotificationStore {
    public static let defaultNotificationEventLimit =
        25_000

    public static let defaultActionRunLimit =
        10_000

    private static let maximumStoredTextLength = 4_096
    private static let currentSchemaVersion: Int32 = 4

    private let databasePath: String
    private let accessMode: NotificationStoreAccessMode

    private var notificationEventLimit: Int

    private var actionRunLimit: Int

    private var notificationEventCount = 0
    private var actionRunCount = 0

    private var db: OpaquePointer?
    
public init(
    path: String,
    accessMode: NotificationStoreAccessMode =
        .readWrite,
    notificationEventLimit: Int =
        NotificationStore
            .defaultNotificationEventLimit,
    actionRunLimit: Int =
        NotificationStore
            .defaultActionRunLimit
) throws {
        precondition(
            notificationEventLimit > 0,
            "Notification event retention must be positive"
        )

        precondition(
            actionRunLimit > 0,
            "Action-run retention must be positive"
        )

        self.databasePath = path
        self.accessMode = accessMode
        self.notificationEventLimit =
            notificationEventLimit
        self.actionRunLimit = actionRunLimit

        let openFlags: Int32

        switch accessMode {
        case .readWrite:
            openFlags =
                SQLITE_OPEN_READWRITE
                    | SQLITE_OPEN_CREATE

        case .readOnly:
            openFlags = SQLITE_OPEN_READONLY
        }

        if sqlite3_open_v2(
            path,
            &db,
            openFlags,
            nil
        ) != SQLITE_OK {
            throw StoreError.openFailed(
                message: lastErrorMessage
            )
        }

        try prepareSchema()

        notificationEventCount = try rowCount(
            in: "notification_events"
        )

        actionRunCount = try rowCount(
            in: "action_runs"
        )

        if accessMode == .readWrite {
            try pruneNotificationEventsIfNeeded()
            try pruneActionRunsIfNeeded()
        }
    }

        public func statistics()
        throws -> NotificationStoreStatistics
    {
        let eventDateRange =
            try notificationEventDateRange()

        return NotificationStoreStatistics(
            notificationEventCount:
                try rowCount(
                    in: "notification_events"
                ),
            actionRunCount:
                try rowCount(
                    in: "action_runs"
                ),
            activeNotificationCount:
                try rowCount(
                    in: "active_notifications"
                ),
            watchSessionCount:
                try rowCount(
                    in: "watch_sessions"
                ),
            oldestNotificationEventDate:
                eventDateRange.oldest,
            newestNotificationEventDate:
                eventDateRange.newest,
            databaseStorageByteCount:
                databaseStorageByteCount(),
            notificationEventLimit:
                notificationEventLimit,
            actionRunLimit:
                actionRunLimit
        )
    }

    public func updateRetentionLimits(
        notificationEventLimit: Int,
        actionRunLimit: Int
    ) throws {
        try requireReadWriteAccess()

        guard notificationEventLimit > 0 else {
            throw StoreError.invalidRetentionLimit(
                message:
                    "Activity event retention must be positive."
            )
        }

        guard actionRunLimit > 0 else {
            throw StoreError.invalidRetentionLimit(
                message:
                    "Action-run retention must be positive."
            )
        }

        self.notificationEventLimit =
            notificationEventLimit

        self.actionRunLimit =
            actionRunLimit

        try pruneNotificationEventsIfNeeded()
        try pruneActionRunsIfNeeded()
    }

    deinit {
        sqlite3_close(db)
    }

    public func insert(
        _ events: [NotificationEvent],
        session: ObservationSession
    ) throws {
        for event in events {
            try insert(event, session: session)
        }
    }

    public func insert(
        _ event: NotificationEvent,
        session: ObservationSession
    ) throws {
        try requireReadWriteAccess()

        let sql = """
        INSERT INTO notification_events (
            session_id,
            timestamp,
            event_type,
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: event.timestamp)
        let sessionID = session.id
        let type = event.type.rawValue
        let notification = event.notification

        bind(sessionID, to: statement, index: 1)
        bind(timestamp, to: statement, index: 2)
        bind(type, to: statement, index: 3)
        bind(notification.key, to: statement, index: 4)
        bind(notification.subrole, to: statement, index: 5)
        bind(notification.axIdentifier, to: statement, index: 6)
        bind(
            storedText(notification.app),
            to: statement,
            index: 7
        )
        bind(
            storedText(notification.title),
            to: statement,
            index: 8
        )
        bind(
            storedText(notification.subtitle),
            to: statement,
            index: 9
        )
        bind(
            storedText(notification.body),
            to: statement,
            index: 10
        )

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(
                message: lastErrorMessage
            )
        }

        notificationEventCount += 1

        try updateActiveNotifications(for: event)
        try pruneNotificationEventsIfNeeded()
    }

    @discardableResult
    public func insert(
        _ result: ActionRunResult,
        session: ObservationSession
    ) throws -> Int64 {
        try requireReadWriteAccess()

        let sql = """
        INSERT INTO action_runs (
            created_at,
            session_id,
            rule_name,
            action_summary,
            resolved_action_summary,
            status,
            verification_status,
            message,
            exit_code,
            stdout,
            stderr,
            event_type,
            event_timestamp,
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        let event = result.event
        let notification = event.notification

        bind(
            formatter.string(from: Date()),
            to: statement,
            index: 1
        )
        bind(session.id, to: statement, index: 2)
        bind(
            storedText(result.ruleName),
            to: statement,
            index: 3
        )
        bind(
            storedText(result.action.summary),
            to: statement,
            index: 4
        )
        bind(
            storedText(result.resolvedAction.summary),
            to: statement,
            index: 5
        )
        bind(result.status.rawValue, to: statement, index: 6)
        bind(
            result.verificationStatus?.rawValue,
            to: statement,
            index: 7
        )
        bind(
            storedText(result.message),
            to: statement,
            index: 8
        )
        bind(result.exitCode, to: statement, index: 9)
        bind(
            storedText(result.stdout),
            to: statement,
            index: 10
        )
        bind(
            storedText(result.stderr),
            to: statement,
            index: 11
        )
        bind(event.type.rawValue, to: statement, index: 12)
        bind(
            formatter.string(from: event.timestamp),
            to: statement,
            index: 13
        )
        bind(notification.key, to: statement, index: 14)
        bind(notification.subrole, to: statement, index: 15)
        bind(
            notification.axIdentifier,
            to: statement,
            index: 16
        )
        bind(
            storedText(notification.app),
            to: statement,
            index: 17
        )
        bind(
            storedText(notification.title),
            to: statement,
            index: 18
        )
        bind(
            storedText(notification.subtitle),
            to: statement,
            index: 19
        )
        bind(
            storedText(notification.body),
            to: statement,
            index: 20
        )

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(
                message: lastErrorMessage
            )
        }
        
        let actionRunID =
            sqlite3_last_insert_rowid(db)

        actionRunCount += 1

        try pruneActionRunsIfNeeded()
        return actionRunID
    }

    public func updateActionVerificationStatus(
        _ status: ActionVerificationStatus,
        forActionRunID actionRunID: Int64
    ) throws {
        try requireReadWriteAccess()

        let sql = """
        UPDATE action_runs
        SET verification_status = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(status.rawValue, to: statement, index: 1)
        sqlite3_bind_int64(statement, 2, actionRunID)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.updateFailed(message: lastErrorMessage)
        }

        guard sqlite3_changes(db) == 1 else {
            throw StoreError.updateFailed(
                message: "No action_runs row found with id \(actionRunID)"
            )
        }
    }

    private func updateActiveNotifications(for event: NotificationEvent) throws {
        switch event.type {
        case .appeared:
            try upsertActiveNotification(event)

        case .disappeared,
             .disappearedUnobserved:
            try deleteActiveNotification(event.notification.key)
        }
    }

    private func upsertActiveNotification(_ event: NotificationEvent) throws {
        let sql = """
        INSERT INTO active_notifications (
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body,
            first_seen_at,
            last_seen_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(notification_key) DO UPDATE SET
            subrole = excluded.subrole,
            ax_identifier = excluded.ax_identifier,
            app = excluded.app,
            title = excluded.title,
            subtitle = excluded.subtitle,
            body = excluded.body,
            last_seen_at = excluded.last_seen_at;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: event.timestamp)
        let notification = event.notification

        bind(notification.key, to: statement, index: 1)
        bind(notification.subrole, to: statement, index: 2)
        bind(notification.axIdentifier, to: statement, index: 3)
        bind(notification.app, to: statement, index: 4)
        bind(notification.title, to: statement, index: 5)
        bind(notification.subtitle, to: statement, index: 6)
        bind(notification.body, to: statement, index: 7)
        bind(timestamp, to: statement, index: 8)
        bind(timestamp, to: statement, index: 9)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(message: lastErrorMessage)
        }
    }

    private func deleteActiveNotification(_ key: String) throws {
        let sql = """
        DELETE FROM active_notifications
        WHERE notification_key = ?;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        bind(key, to: statement, index: 1)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(message: lastErrorMessage)
        }
    }

    public func startSession(
        _ session: ObservationSession
    ) throws {
        try requireReadWriteAccess()

        let sql = """
        INSERT OR IGNORE INTO watch_sessions (
            id,
            started_at
        ) VALUES (?, ?);
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        bind(session.id, to: statement, index: 1)
        bind(formatter.string(from: session.startedAt), to: statement, index: 2)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(message: lastErrorMessage)
        }
    }

    public func endSession(
        _ session: ObservationSession,
        endedAt: Date = Date()
    ) throws {
        try requireReadWriteAccess()

        let sql = """
        UPDATE watch_sessions
        SET ended_at = ?
        WHERE id = ?;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        bind(formatter.string(from: endedAt), to: statement, index: 1)
        bind(session.id, to: statement, index: 2)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(message: lastErrorMessage)
        }
    }

    public func loadActiveNotifications() throws -> [VisibleNotification] {
        let sql = """
        SELECT
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body
        FROM active_notifications
        ORDER BY last_seen_at;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        var notifications: [VisibleNotification] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let notification = VisibleNotification(
                key: columnText(statement, index: 0),
                subrole: columnText(statement, index: 1),
                axIdentifier: columnText(statement, index: 2),
                app: columnText(statement, index: 3),
                title: columnText(statement, index: 4),
                subtitle: columnText(statement, index: 5),
                body: columnText(statement, index: 6)
            )
            notifications.append(notification)
        }

        return notifications
    }

    public func recentEvents(limit: Int = 20) throws -> [NotificationEventRecord] {
        let safeLimit = max(1, min(limit, 1000))

        let sql = """
        SELECT
            id,
            session_id,
            timestamp,
            event_type,
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body
        FROM (
            SELECT
                id,
                session_id,
                timestamp,
                event_type,
                notification_key,
                subrole,
                ax_identifier,
                app,
                title,
                subtitle,
                body
            FROM notification_events
            ORDER BY id DESC
            LIMIT \(safeLimit)
        )
        ORDER BY id ASC;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        var records: [NotificationEventRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let sessionID = columnText(statement, index: 1)
            let timestampString = columnText(statement, index: 2)
            let eventTypeString = columnText(statement, index: 3)

            guard let eventType = NotificationEventType(rawValue: eventTypeString) else {
                continue
            }

            let timestamp = formatter.date(from: timestampString) ?? Date(timeIntervalSince1970: 0)

            let notification = VisibleNotification(
                key: columnText(statement, index: 4),
                subrole: columnText(statement, index: 5),
                axIdentifier: columnText(statement, index: 6),
                app: columnText(statement, index: 7),
                title: columnText(statement, index: 8),
                subtitle: columnText(statement, index: 9),
                body: columnText(statement, index: 10)
            )

            let event = NotificationEvent(
                type: eventType,
                notification: notification,
                timestamp: timestamp
            )

            records.append(
                NotificationEventRecord(
                    id: id,
                    sessionID: sessionID,
                    event: event
                )
            )
        }

        return records
    }

    public func recentAppearanceEvents(
        limit: Int = 20
    ) throws -> [NotificationEventRecord] {
        let safeLimit = max(1, min(limit, 1_000))

        let sql = """
        SELECT
            id,
            session_id,
            timestamp,
            event_type,
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body
        FROM (
            SELECT
                id,
                session_id,
                timestamp,
                event_type,
                notification_key,
                subrole,
                ax_identifier,
                app,
                title,
                subtitle,
                body
            FROM notification_events
            WHERE event_type = 'appeared'
            ORDER BY id DESC
            LIMIT \(safeLimit)
        )
        ORDER BY id ASC;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        var records: [NotificationEventRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let sessionID = columnText(
                statement,
                index: 1
            )

            let timestampString = columnText(
                statement,
                index: 2
            )

            let timestamp =
                formatter.date(from: timestampString)
                ?? Date(timeIntervalSince1970: 0)

            let notification = VisibleNotification(
                key: columnText(statement, index: 4),
                subrole: columnText(statement, index: 5),
                axIdentifier: columnText(statement, index: 6),
                app: columnText(statement, index: 7),
                title: columnText(statement, index: 8),
                subtitle: columnText(statement, index: 9),
                body: columnText(statement, index: 10)
            )

            let event = NotificationEvent(
                type: .appeared,
                notification: notification,
                timestamp: timestamp
            )

            records.append(
                NotificationEventRecord(
                    id: id,
                    sessionID: sessionID,
                    event: event
                )
            )
        }

        return records
    }

    public func recentActionRuns(limit: Int = 20) throws -> [ActionRunRecord] {
        let safeLimit = max(1, min(limit, 1000))

        let sql = """
        SELECT
            id,
            created_at,
            session_id,
            rule_name,
            action_summary,
            resolved_action_summary,
            status,
            verification_status,
            message,
            exit_code,
            stdout,
            stderr,
            event_type,
            event_timestamp,
            notification_key,
            subrole,
            ax_identifier,
            app,
            title,
            subtitle,
            body
        FROM (
            SELECT
                id,
                created_at,
                session_id,
                rule_name,
                action_summary,
                resolved_action_summary,
                status,
                verification_status,
                message,
                exit_code,
                stdout,
                stderr,
                event_type,
                event_timestamp,
                notification_key,
                subrole,
                ax_identifier,
                app,
                title,
                subtitle,
                body
            FROM action_runs
            ORDER BY id DESC
            LIMIT \(safeLimit)
        )
        ORDER BY id ASC;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        let formatter = ISO8601DateFormatter()
        var records: [ActionRunRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)

            let createdAtString = columnText(statement, index: 1)
            let sessionID = columnText(statement, index: 2)
            let ruleName = columnText(statement, index: 3)
            let actionSummary = columnText(statement, index: 4)
            let resolvedActionSummary = columnText(statement, index: 5)
            let statusString = columnText(statement, index: 6)
            let verificationStatusString = columnText(statement, index: 7)
            let message = columnText(statement, index: 8)

            let exitCode: Int32?
            if sqlite3_column_type(statement, 9) == SQLITE_NULL {
                exitCode = nil
            } else {
                exitCode = sqlite3_column_int(statement, 9)
            }

            let stdout = columnText(statement, index: 10)
            let stderr = columnText(statement, index: 11)

            let eventTypeString = columnText(statement, index: 12)
            let eventTimestampString = columnText(statement, index: 13)

            guard let status = ActionRunStatus(rawValue: statusString) else {
                continue
            }

            guard let eventType = NotificationEventType(rawValue: eventTypeString) else {
                continue
            }

            let verificationStatus = ActionVerificationStatus(
                rawValue: verificationStatusString
            )

            let createdAt = formatter.date(from: createdAtString) ?? Date(timeIntervalSince1970: 0)
            let eventTimestamp = formatter.date(from: eventTimestampString) ?? Date(timeIntervalSince1970: 0)

            let notification = VisibleNotification(
                key: columnText(statement, index: 14),
                subrole: columnText(statement, index: 15),
                axIdentifier: columnText(statement, index: 16),
                app: columnText(statement, index: 17),
                title: columnText(statement, index: 18),
                subtitle: columnText(statement, index: 19),
                body: columnText(statement, index: 20)
            )

            records.append(
                ActionRunRecord(
                    id: id,
                    createdAt: createdAt,
                    sessionID: sessionID,
                    ruleName: ruleName,
                    actionSummary: actionSummary,
                    resolvedActionSummary: resolvedActionSummary,
                    status: status,
                    verificationStatus: verificationStatus,
                    message: message,
                    exitCode: exitCode,
                    stdout: stdout,
                    stderr: stderr,
                    eventType: eventType,
                    eventTimestamp: eventTimestamp,
                    notification: notification
                )
            )
        }

        return records
    }

    private func prepareSchema() throws {
        let foundVersion = try schemaVersion()

        guard
            foundVersion
                <= NotificationStore.currentSchemaVersion
        else {
            throw StoreError.schemaTooNew(
                foundVersion: foundVersion,
                supportedVersion:
                    NotificationStore.currentSchemaVersion
            )
        }

        if foundVersion
            == NotificationStore.currentSchemaVersion
        {
            return
        }

        let containsUserTables = try hasUserTables()

        if foundVersion == 0 && !containsUserTables {
            guard accessMode == .readWrite else {
                throw StoreError.schemaRequiresMigration(
                    foundVersion: foundVersion,
                    requiredVersion:
                        NotificationStore.currentSchemaVersion
                )
            }

            try createTables()

            try setSchemaVersion(
                NotificationStore.currentSchemaVersion
            )

            return
        }

        guard try isRecognizedLegacySchema() else {
            throw StoreError.unrecognizedLegacySchema
        }

        guard accessMode == .readWrite else {
            throw StoreError.schemaRequiresMigration(
                foundVersion: foundVersion,
                requiredVersion:
                    NotificationStore.currentSchemaVersion
            )
        }

        try createTables()
        try migrateSchema()

        try setSchemaVersion(
            NotificationStore.currentSchemaVersion
        )
    }

    private func schemaVersion() throws -> Int32 {
        let sql = "PRAGMA user_version;"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.queryFailed(
                message: lastErrorMessage
            )
        }

        return sqlite3_column_int(statement, 0)
    }

    private func setSchemaVersion(
        _ version: Int32
    ) throws {
        let sql =
            "PRAGMA main.user_version = \(Int(version));"

        guard sqlite3_exec(
            db,
            sql,
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw StoreError.migrationFailed(
                message: lastErrorMessage
            )
        }

        let storedVersion = try schemaVersion()

        guard storedVersion == version else {
            throw StoreError.migrationFailed(
                message:
                    "Failed to set database schema version " +
                    "to \(version); database reports " +
                    "\(storedVersion)."
            )
        }
    }

    private func migrateSchema() throws {
        guard try !columnExists("verification_status", in: "action_runs") else {
            return
        }

        let sql = """
        ALTER TABLE action_runs
        ADD COLUMN verification_status TEXT;
        """

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.migrationFailed(message: lastErrorMessage)
        }
    }

    private func tableExists(
        _ tableName: String
    ) throws -> Bool {
        let sql = """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table'
        AND name = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(
            statement,
            1,
            tableName,
            -1,
            SQLITE_TRANSIENT
        )

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func hasUserTables() throws -> Bool {
        let sql = """
        SELECT 1
        FROM sqlite_master
        WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        LIMIT 1;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return true

        case SQLITE_DONE:
            return false

        default:
            throw StoreError.queryFailed(
                message: lastErrorMessage
            )
        }
    }

    private func isRecognizedLegacySchema()
        throws -> Bool
    {
        let requiredColumns: [String: [String]] = [
            "notification_events": [
                "id",
                "session_id",
                "timestamp",
                "event_type",
                "notification_key",
                "subrole",
                "ax_identifier",
                "app",
                "title",
                "subtitle",
                "body",
            ],

            "active_notifications": [
                "notification_key",
                "subrole",
                "ax_identifier",
                "app",
                "title",
                "subtitle",
                "body",
                "first_seen_at",
                "last_seen_at",
            ],

            "watch_sessions": [
                "id",
                "started_at",
                "ended_at",
            ],

            "action_runs": [
                "id",
                "created_at",
                "session_id",
                "rule_name",
                "action_summary",
                "resolved_action_summary",
                "status",
                "message",
                "exit_code",
                "stdout",
                "stderr",
                "event_type",
                "event_timestamp",
                "notification_key",
                "subrole",
                "ax_identifier",
                "app",
                "title",
                "subtitle",
                "body",
            ],
        ]

        for (
            tableName,
            columnNames
        ) in requiredColumns {
            guard try tableExists(tableName) else {
                return false
            }

            for columnName in columnNames {
                guard try columnExists(
                    columnName,
                    in: tableName
                ) else {
                    return false
                }
            }
        }

        return true
    }

    private func columnExists(
        _ columnName: String,
        in tableName: String
    ) throws -> Bool {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed(message: lastErrorMessage)
        }

        defer {
            sqlite3_finalize(statement)
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if columnText(statement, index: 1) == columnName {
                return true
            }
        }

        return false
    }

    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS notification_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            event_type TEXT NOT NULL,
            notification_key TEXT NOT NULL,
            subrole TEXT NOT NULL,
            ax_identifier TEXT NOT NULL,
            app TEXT NOT NULL,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            body TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS active_notifications (
            notification_key TEXT PRIMARY KEY,
            subrole TEXT NOT NULL,
            ax_identifier TEXT NOT NULL,
            app TEXT NOT NULL,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            body TEXT NOT NULL,
            first_seen_at TEXT NOT NULL,
            last_seen_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS watch_sessions (
            id TEXT PRIMARY KEY,
            started_at TEXT NOT NULL,
            ended_at TEXT
        );

        CREATE TABLE IF NOT EXISTS action_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            created_at TEXT NOT NULL,
            session_id TEXT NOT NULL,
            rule_name TEXT NOT NULL,
            action_summary TEXT NOT NULL,
            resolved_action_summary TEXT NOT NULL,
            status TEXT NOT NULL,
            verification_status TEXT,
            message TEXT NOT NULL,
            exit_code INTEGER,
            stdout TEXT NOT NULL,
            stderr TEXT NOT NULL,
            event_type TEXT NOT NULL,
            event_timestamp TEXT NOT NULL,
            notification_key TEXT NOT NULL,
            subrole TEXT NOT NULL,
            ax_identifier TEXT NOT NULL,
            app TEXT NOT NULL,
            title TEXT NOT NULL,
            subtitle TEXT NOT NULL,
            body TEXT NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_action_runs_created_at
        ON action_runs(created_at);

        CREATE INDEX IF NOT EXISTS idx_action_runs_session
        ON action_runs(session_id);

        CREATE INDEX IF NOT EXISTS idx_action_runs_status
        ON action_runs(status);

        CREATE INDEX IF NOT EXISTS idx_action_runs_notification_key
        ON action_runs(notification_key);

        CREATE INDEX IF NOT EXISTS idx_notification_events_timestamp
        ON notification_events(timestamp);

        CREATE INDEX IF NOT EXISTS idx_notification_events_type
        ON notification_events(event_type);

        CREATE INDEX IF NOT EXISTS idx_notification_events_app
        ON notification_events(app);

        CREATE INDEX IF NOT EXISTS idx_notification_events_key
        ON notification_events(notification_key);

        CREATE INDEX IF NOT EXISTS idx_notification_events_ax_identifier
        ON notification_events(ax_identifier);

        CREATE INDEX IF NOT EXISTS idx_notification_events_subrole
        ON notification_events(subrole);

        CREATE INDEX IF NOT EXISTS idx_notification_events_session
        ON notification_events(session_id);

        """

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.createTableFailed(message: lastErrorMessage)
        }
    }

    private func notificationEventDateRange()
        throws -> (
            oldest: Date?,
            newest: Date?
        )
    {
        let sql = """
        SELECT
            MIN(timestamp),
            MAX(timestamp)
        FROM notification_events;
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.queryFailed(
                message: lastErrorMessage
            )
        }

        let formatter = ISO8601DateFormatter()

        return (
            oldest: formatter.date(
                from: columnText(
                    statement,
                    index: 0
                )
            ),
            newest: formatter.date(
                from: columnText(
                    statement,
                    index: 1
                )
            )
        )
    }

    private func databaseStorageByteCount()
        -> Int64
    {
        let paths = [
            databasePath,
            databasePath + "-wal",
            databasePath + "-shm",
        ]

        return paths.reduce(0) {
            partialResult,
            path in

            guard
                let attributes =
                    try? FileManager.default
                        .attributesOfItem(
                            atPath: path
                        ),
                let size =
                    attributes[.size] as? NSNumber
            else {
                return partialResult
            }

            return partialResult
                + size.int64Value
        }
    }

    private func rowCount(
        in tableName: String
    ) throws -> Int {
        let sql =
            "SELECT COUNT(*) FROM \(tableName);"

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.queryFailed(
                message: lastErrorMessage
            )
        }

        return Int(
            sqlite3_column_int64(statement, 0)
        )
    }

    private func pruneNotificationEventsIfNeeded()
        throws
    {
        guard notificationEventCount
            > notificationEventLimit
        else {
            return
        }

        let deletionCount =
            notificationEventCount
                - notificationEventLimit

        try deleteOldestRows(
            from: "notification_events",
            count: deletionCount
        )

        notificationEventCount -= deletionCount
    }

    private func pruneActionRunsIfNeeded()
        throws
    {
        guard actionRunCount > actionRunLimit else {
            return
        }

        let deletionCount =
            actionRunCount - actionRunLimit

        try deleteOldestRows(
            from: "action_runs",
            count: deletionCount
        )

        actionRunCount -= deletionCount
    }

    private func deleteOldestRows(
        from tableName: String,
        count: Int
    ) throws {
        guard count > 0 else {
            return
        }

        let sql = """
        DELETE FROM \(tableName)
        WHERE id IN (
            SELECT id
            FROM \(tableName)
            ORDER BY id ASC
            LIMIT ?
        );
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(
            db,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw StoreError.prepareFailed(
                message: lastErrorMessage
            )
        }

        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(
            statement,
            1,
            Int64(count)
        )

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.deleteFailed(
                message: lastErrorMessage
            )
        }
    }

    private func storedText(
        _ value: String
    ) -> String {
        String(
            value.prefix(
                Self.maximumStoredTextLength
            )
        )
    }

    private func bind(_ string: String, to statement: OpaquePointer?, index: Int32) {
        sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ string: String?, to statement: OpaquePointer?, index: Int32) {
        if let string {
            bind(string, to: statement, index: index)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ int: Int32?, to statement: OpaquePointer?, index: Int32) {
        if let int {
            sqlite3_bind_int(statement, index, int)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func columnText(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else {
            return ""
        }

        return String(cString: cString)
    }

    private func requireReadWriteAccess() throws {
        guard accessMode == .readWrite else {
            throw StoreError.readOnlyMutation
        }
    }

    private var lastErrorMessage: String {
        if let db {
            return String(cString: sqlite3_errmsg(db))
        }

        return "Unknown SQLite error"
    }
}

public enum StoreError: Error {
    case openFailed(message: String)
    case createTableFailed(message: String)
    case prepareFailed(message: String)
    case queryFailed(message: String)
    case insertFailed(message: String)
    case updateFailed(message: String)
    case deleteFailed(message: String)
    case migrationFailed(message: String)

    case schemaRequiresMigration(
        foundVersion: Int32,
        requiredVersion: Int32
    )

    case schemaTooNew(
        foundVersion: Int32,
        supportedVersion: Int32
    )

    case unrecognizedLegacySchema

    case invalidRetentionLimit(message: String)
    case readOnlyMutation
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

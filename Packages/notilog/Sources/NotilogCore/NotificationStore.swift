import Foundation
import SQLite3

public final class NotificationStore {
    private var db: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw StoreError.openFailed(message: lastErrorMessage)
        }

        try createTables()
        try migrateSchema()
    }

    deinit {
        sqlite3_close(db)
    }

    public func insert(_ events: [NotificationEvent], session: ObservationSession) throws {
        for event in events {
            try insert(event, session: session)
        }
    }

    public func insert(_ event: NotificationEvent, session: ObservationSession) throws {
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
        bind(notification.app, to: statement, index: 7)
        bind(notification.title, to: statement, index: 8)
        bind(notification.subtitle, to: statement, index: 9)
        bind(notification.body, to: statement, index: 10)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(message: lastErrorMessage)
        }

        try updateActiveNotifications(for: event)
    }

    @discardableResult
    public func insert(
        _ result: ActionRunResult,
        session: ObservationSession
    ) throws -> Int64 {
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

        bind(formatter.string(from: Date()), to: statement, index: 1)
        bind(session.id, to: statement, index: 2)
        bind(result.ruleName, to: statement, index: 3)
        bind(result.action.summary, to: statement, index: 4)
        bind(result.resolvedAction.summary, to: statement, index: 5)
        bind(result.status.rawValue, to: statement, index: 6)
        bind(result.verificationStatus?.rawValue, to: statement, index: 7)
        bind(result.message, to: statement, index: 8)
        bind(result.exitCode, to: statement, index: 9)
        bind(result.stdout, to: statement, index: 10)
        bind(result.stderr, to: statement, index: 11)
        bind(event.type.rawValue, to: statement, index: 12)
        bind(formatter.string(from: event.timestamp), to: statement, index: 13)
        bind(notification.key, to: statement, index: 14)
        bind(notification.subrole, to: statement, index: 15)
        bind(notification.axIdentifier, to: statement, index: 16)
        bind(notification.app, to: statement, index: 17)
        bind(notification.title, to: statement, index: 18)
        bind(notification.subtitle, to: statement, index: 19)
        bind(notification.body, to: statement, index: 20)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed(message: lastErrorMessage)
        }

        return sqlite3_last_insert_rowid(db)
    }

    public func updateActionVerificationStatus(
        _ status: ActionVerificationStatus,
        forActionRunID actionRunID: Int64
    ) throws {
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

    public func startSession(_ session: ObservationSession) throws {
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

    public func endSession(_ session: ObservationSession, endedAt: Date = Date()) throws {
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

    private func columnExists(_ columnName: String, in tableName: String) throws -> Bool {
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

        PRAGMA user_version = 4;
        """

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.createTableFailed(message: lastErrorMessage)
        }
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
    case insertFailed(message: String)
    case updateFailed(message: String)
    case migrationFailed(message: String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

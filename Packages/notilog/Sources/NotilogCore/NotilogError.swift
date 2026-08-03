import Darwin
import Foundation

public enum NotilogError:
    Error,
    LocalizedError,
    Equatable,
    Sendable
{
    case monitorAlreadyRunning

    case monitoringLockOpenFailed(
        lockFileURL: URL,
        errorCode: Int32
    )

    case monitoringLockFailed(
        lockFileURL: URL,
        errorCode: Int32
    )

    case databaseNotFound(
        path: String
    )

    case schemaRequiresMigration(
        foundVersion: Int32,
        requiredVersion: Int32
    )

    case schemaTooNew(
        foundVersion: Int32,
        supportedVersion: Int32
    )

    case unrecognizedLegacySchema

    case invalidRetentionConfiguration(
        message: String
    )

    case retentionConfigurationReadFailed(
        path: String,
        message: String
    )

    case retentionConfigurationWriteFailed(
        path: String,
        message: String
    )

    case databaseOpenFailed(
        message: String
    )

    case databaseCreateSchemaFailed(
        message: String
    )

    case databasePrepareFailed(
        message: String
    )

    case databaseQueryFailed(
        message: String
    )

    case databaseInsertFailed(
        message: String
    )

    case databaseUpdateFailed(
        message: String
    )

    case databaseDeleteFailed(
        message: String
    )

    case databaseMigrationFailed(
        message: String
    )

    case readOnlyMutation

    public var errorDescription: String? {
        switch self {
        case .monitorAlreadyRunning:
            return "Notilog monitoring is already running."

        case let .monitoringLockOpenFailed(
            lockFileURL,
            errorCode
        ):
            return Self.lockErrorDescription(
                prefix:
                    "Could not open the monitoring lock",
                lockFileURL: lockFileURL,
                errorCode: errorCode
            )

        case let .monitoringLockFailed(
            lockFileURL,
            errorCode
        ):
            return Self.lockErrorDescription(
                prefix:
                    "Could not acquire the monitoring lock",
                lockFileURL: lockFileURL,
                errorCode: errorCode
            )

        case let .databaseNotFound(path):
            return "Notilog database not found at \(path)."

        case let .schemaRequiresMigration(
            foundVersion,
            requiredVersion
        ):
            return
                "Database schema version \(foundVersion) " +
                "requires migration to version " +
                "\(requiredVersion)."

        case let .schemaTooNew(
            foundVersion,
            supportedVersion
        ):
            return
                "Database schema version \(foundVersion) " +
                "is newer than supported version " +
                "\(supportedVersion)."

        case .unrecognizedLegacySchema:
            return
                "The database has an unrecognized " +
                "legacy schema."

        case let .invalidRetentionConfiguration(
            message
        ):
            return
                "Invalid retention configuration: " +
                message

        case let .retentionConfigurationReadFailed(
            path,
            message
        ):
            return
                "Could not read retention configuration " +
                "at \(path): \(message)"

        case let .retentionConfigurationWriteFailed(
            path,
            message
        ):
            return
                "Could not write retention configuration " +
                "at \(path): \(message)"

        case let .databaseOpenFailed(message):
            return
                "Could not open the database: " +
                message

        case let .databaseCreateSchemaFailed(message):
            return
                "Could not create the database schema: " +
                message

        case let .databasePrepareFailed(message):
            return
                "Could not prepare a database operation: " +
                message

        case let .databaseQueryFailed(message):
            return
                "Database query failed: " +
                message

        case let .databaseInsertFailed(message):
            return
                "Database insert failed: " +
                message

        case let .databaseUpdateFailed(message):
            return
                "Database update failed: " +
                message

        case let .databaseDeleteFailed(message):
            return
                "Database deletion failed: " +
                message

        case let .databaseMigrationFailed(message):
            return
                "Database migration failed: " +
                message

        case .readOnlyMutation:
            return
                "The database was opened read-only " +
                "and cannot be modified."
        }
    }

    private static func lockErrorDescription(
        prefix: String,
        lockFileURL: URL,
        errorCode: Int32
    ) -> String {
        let systemMessage =
            String(cString: strerror(errorCode))

        return
            "\(prefix) at \(lockFileURL.path): " +
            systemMessage
    }
}

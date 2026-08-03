import Foundation

public struct RetentionConfiguration:
    Codable,
    Equatable,
    Sendable
{
    public static let defaultNotificationEventLimit =
        25_000

    public static let defaultActionRunLimit =
        10_000

    public static let notificationEventLimitRange =
        1_000...100_000

    public static let actionRunLimitRange =
        1_000...50_000

    public static let defaults =
        RetentionConfiguration(
            uncheckedNotificationEventLimit:
                defaultNotificationEventLimit,
            uncheckedActionRunLimit:
                defaultActionRunLimit
        )

    public let notificationEventLimit: Int
    public let actionRunLimit: Int

    public init(
        notificationEventLimit: Int =
            Self.defaultNotificationEventLimit,
        actionRunLimit: Int =
            Self.defaultActionRunLimit
    ) throws {
        guard Self.notificationEventLimitRange
            .contains(notificationEventLimit)
        else {
            throw NotilogError
                .invalidRetentionConfiguration(
                    message:
                        "notificationEventLimit must be " +
                        "between " +
                        "\(Self.notificationEventLimitRange.lowerBound) " +
                        "and " +
                        "\(Self.notificationEventLimitRange.upperBound)."
                )
        }

        guard Self.actionRunLimitRange
            .contains(actionRunLimit)
        else {
            throw NotilogError
                .invalidRetentionConfiguration(
                    message:
                        "actionRunLimit must be between " +
                        "\(Self.actionRunLimitRange.lowerBound) " +
                        "and " +
                        "\(Self.actionRunLimitRange.upperBound)."
                )
        }

        self.notificationEventLimit =
            notificationEventLimit

        self.actionRunLimit =
            actionRunLimit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        let notificationEventLimit =
            try container.decode(
                Int.self,
                forKey: .notificationEventLimit
            )

        let actionRunLimit =
            try container.decode(
                Int.self,
                forKey: .actionRunLimit
            )

        do {
            try self.init(
                notificationEventLimit:
                    notificationEventLimit,
                actionRunLimit:
                    actionRunLimit
            )
        } catch {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath:
                        container.codingPath,
                    debugDescription:
                        error.localizedDescription,
                    underlyingError: error
                )
            )
        }
    }

    private init(
        uncheckedNotificationEventLimit:
            Int,
        uncheckedActionRunLimit:
            Int
    ) {
        self.notificationEventLimit =
            uncheckedNotificationEventLimit

        self.actionRunLimit =
            uncheckedActionRunLimit
    }
}
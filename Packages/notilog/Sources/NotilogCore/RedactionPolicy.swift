import Foundation

public enum RedactionField: String, CaseIterable, Hashable, Sendable {
    case app
    case title
    case subtitle
    case body
    case attachments
}

public struct RedactionPolicy: Equatable, Sendable {
    public static let defaultFields: Set<RedactionField> = [
        .title,
        .subtitle,
        .body,
        .attachments
    ]

    public static let allFields = Set(RedactionField.allCases)

    public static let disabled = RedactionPolicy(fields: [])
    public static let defaultPolicy = RedactionPolicy(fields: defaultFields)
    public static let all = RedactionPolicy(fields: allFields)

    public let fields: Set<RedactionField>

    public var isEnabled: Bool {
        !fields.isEmpty
    }
    
    public var fieldNames: [String] {
        RedactionField.allCases
            .filter { fields.contains($0) }
            .map(\.rawValue)
    }

    public init(fields: Set<RedactionField>) {
        self.fields = fields
    }

    public func redacts(_ field: RedactionField) -> Bool {
        fields.contains(field)
    }

    public static func parse(_ value: String?) throws -> RedactionPolicy {
        guard let value else {
            return .defaultPolicy
        }

        let normalizedValue = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch normalizedValue {
        case "default":
            return .defaultPolicy

        case "all":
            return .all

        case "":
            throw RedactionPolicyParseError.emptySelection

        default:
            break
        }

        let fieldNames = normalizedValue.split(
            separator: ",",
            omittingEmptySubsequences: false
        )

        var parsedFields: Set<RedactionField> = []

        for fieldName in fieldNames {
            let normalizedFieldName = fieldName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !normalizedFieldName.isEmpty else {
                throw RedactionPolicyParseError.emptyField
            }

            guard let field = RedactionField(
                rawValue: normalizedFieldName
            ) else {
                throw RedactionPolicyParseError.unknownField(
                    normalizedFieldName
                )
            }

            parsedFields.insert(field)
        }

        return RedactionPolicy(fields: parsedFields)
    }
    
    public func applying(
        to notification: VisibleNotification
    ) -> VisibleNotification {
        VisibleNotification(
            key: notification.key,
            subrole: notification.subrole,
            axIdentifier: notification.axIdentifier,
            app: redactedValue(
                notification.app,
                field: .app
            ),
            title: redactedValue(
                notification.title,
                field: .title
            ),
            subtitle: redactedValue(
                notification.subtitle,
                field: .subtitle
            ),
            body: redactedValue(
                notification.body,
                field: .body
            )
        )
    }

    public func applying(
        to event: NotificationEvent
    ) -> NotificationEvent {
        NotificationEvent(
            type: event.type,
            notification: applying(to: event.notification),
            timestamp: event.timestamp
        )
    }

    public func applying(
        to result: ActionRunResult
    ) -> ActionRunResult {
        guard isEnabled else {
            return result
        }
    
        let outputMessage: String
    
        if let exitCode = result.exitCode {
            outputMessage =
                "status: \(result.status.rawValue), exit code: \(exitCode)"
        } else {
            outputMessage = "status: \(result.status.rawValue)"
        }
    
        return ActionRunResult(
            ruleName: result.ruleName,
            action: result.action,
            resolvedAction: redactedResolvedAction(
                result.resolvedAction
            ),
            event: applying(to: result.event),
            status: result.status,
            message: outputMessage,
            exitCode: result.exitCode,
            stdout: redactedActionOutput(result.stdout),
            stderr: redactedActionOutput(result.stderr),
            verificationStatus: result.verificationStatus
        )
    }

    private func redactedResolvedAction(
        _ action: ResolvedNotificationAction
    ) -> ResolvedNotificationAction {
        switch action {
        case .dryRunLog:
            return .dryRunLog(
                message: "[SUPPRESSED BY REDACTION]"
            )

        case .exec(let command, let arguments):
            return .exec(
                command: command,
                arguments: arguments.map { _ in
                    "[REDACTED]"
                }
            )

        case .shutUpMacDismiss(
            let command,
            let notificationKey
        ):
            return .shutUpMacDismiss(
                command: command,
                notificationKey: notificationKey
            )
        }
    }

    private func redactedActionOutput(
        _ value: String
    ) -> String {
        guard !value.isEmpty else {
            return ""
        }
    
        return "[SUPPRESSED BY REDACTION]"
    }

    private func redactedValue(
        _ value: String,
        field: RedactionField
    ) -> String {
        guard redacts(field), !value.isEmpty else {
            return value
        }

        return "[REDACTED]"
    }
}
    

public enum RedactionPolicyParseError: LocalizedError, Equatable {
    case emptySelection
    case emptyField
    case unknownField(String)

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Redaction field selection cannot be empty."

        case .emptyField:
            return "Redaction field list contains an empty field."

        case .unknownField(let field):
            let availableFields = RedactionField.allCases
                .map(\.rawValue)
                .joined(separator: ", ")

            return """
            Unknown redaction field "\(field)". Available fields: \
            \(availableFields).
            """
        }
    }
}

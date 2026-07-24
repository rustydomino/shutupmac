import Foundation

public enum ResolvedNotificationAction: Equatable {
    case dryRunLog(message: String)
    case exec(command: String, arguments: [String])
    case shutUpMacDismiss(command: String, notificationKey: String)

    public var summary: String {
        switch self {
        case .dryRunLog(let message):
            return message

        case .exec(let command, let arguments):
            return ([command] + arguments).joined(separator: " ")

        case .shutUpMacDismiss(let command, let notificationKey):
            return ([
                "ShutUpMac dismiss:",
                command,
                "--dismiss-key",
                notificationKey
            ]).joined(separator: " ")
        }
    }
}

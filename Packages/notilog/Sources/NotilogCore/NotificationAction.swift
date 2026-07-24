import Foundation

public enum NotificationAction {
    public static let defaultShutUpMacCommand =
        "/Applications/ShutUpMac.app/Contents/Helpers/shutupmac-cli"

    case dryRunLog(message: String)
    case exec(command: String, arguments: [String])
    case shutUpMacDismiss(command: String)

    public var summary: String {
        switch self {
        case .dryRunLog(let message):
            return message

        case .exec(let command, let arguments):
            return ([command] + arguments).joined(separator: " ")

        case .shutUpMacDismiss(let command):
            return "ShutUpMac dismiss notification via \(command)"
        }
    }
}

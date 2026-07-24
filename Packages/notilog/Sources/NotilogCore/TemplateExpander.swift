import Foundation

public struct TemplateExpander {
    public init() {}

    public func expand(_ template: String, for event: NotificationEvent) -> String {
        var result = template

        for (key, value) in values(for: event) {
            result = result.replacingOccurrences(
                of: "{{\(key)}}",
                with: value
            )
        }

        return result
    }

    private func values(for event: NotificationEvent) -> [String: String] {
        let formatter = ISO8601DateFormatter()
        let notification = event.notification

        return [
            "event.type": event.type.rawValue,
            "event.timestamp": formatter.string(from: event.timestamp),

            "notification.key": notification.key,
            "notification.subrole": notification.subrole,
            "notification.axIdentifier": notification.axIdentifier,
            "notification.app": notification.app,
            "notification.title": notification.title,
            "notification.subtitle": notification.subtitle,
            "notification.body": notification.body
        ]
    }
}
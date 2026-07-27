import Foundation

public enum BuiltInAutomationRules {
    public static func appearedNotificationProbe() -> NotificationRule {
        NotificationRule(
            id: UUID(
                uuidString: "00000000-0000-0000-0000-000000000001"
            )!,
            name: "appeared notification",
            criteria: NotificationMatchCriteria(
                eventTypes: [.appeared]
            ),
            actions: [
                .exec(
                    command: "/usr/bin/true",
                    arguments: [
                        "--notification-key",
                        "{{notification.key}}"
                    ]
                )
            ]
        )
    }

    public static func probeRules() -> [NotificationRule] {
        [
            appearedNotificationProbe()
        ]
    }
}

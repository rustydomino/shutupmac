import Foundation

public enum BuiltInAutomationRules {
    public static func appearedNotificationProbe() -> NotificationRule {
        NotificationRule(
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
public enum ActionVerificationEvaluator {
    public static func evaluate(
        notificationKey: String,
        visibleNotifications: [VisibleNotification]
    ) -> ActionVerificationStatus {
        let notificationIsStillVisible = visibleNotifications.contains {
            $0.key == notificationKey
        }

        return notificationIsStillVisible
            ? .definitelyFailed
            : .probablySucceeded
    }
}

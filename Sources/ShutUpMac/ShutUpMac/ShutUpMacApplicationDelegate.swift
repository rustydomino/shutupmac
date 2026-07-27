import AppKit

@MainActor
final class ShutUpMacApplicationDelegate: NSObject, NSApplicationDelegate {
    let activityStore = ActivityStore()

    private lazy var notilogMonitoringController =
        NotilogMonitoringController(
            onHistoricalRecords: { [weak self] records in
                self?.activityStore.loadHistoricalRecords(
                    records
                )
            },
            onActivityItems: { [weak self] activityItems in
                self?.activityStore.append(
                    activityItems
                )
            }
        )

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        let isAccessibilityTrusted =
            AccessibilityPermission.isTrusted(prompt: true)

        print(
            "Notilog monitoring Accessibility trusted: "
            + "\(isAccessibilityTrusted)"
        )

        guard isAccessibilityTrusted else {
            print(
                "Notilog monitoring was not started because "
                + "Accessibility permission is unavailable."
            )
            return
        }

        notilogMonitoringController.start()
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        notilogMonitoringController.stop()
    }
}

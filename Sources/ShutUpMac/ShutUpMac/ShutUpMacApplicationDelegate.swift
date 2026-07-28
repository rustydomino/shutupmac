import AppKit
import NotilogCore

@MainActor
final class ShutUpMacApplicationDelegate: NSObject, NSApplicationDelegate {
    let activityStore = ActivityStore()

    private let runtimePaths =
        NotilogRuntimePaths.legacyNotilogDefault()

    private(set) lazy var automationConfigurationStore =
        AutomationConfigurationStore(
            configURL: runtimePaths.config
        )

    private lazy var notilogMonitoringController =
        NotilogMonitoringController(
            runtimePaths: runtimePaths,
            initialConfiguration:
                automationConfigurationStore.configuration,
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

    func saveAutomationConfiguration(
        _ candidate: AutomationConfig
    ) {
        automationConfigurationStore.saveAndActivate(
            candidate,
            using: notilogMonitoringController
        )
    }

    func reloadAutomationConfiguration() {
        automationConfigurationStore.reloadFromDisk(
            using: notilogMonitoringController
        )
    }

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

        guard automationConfigurationStore.load() != nil else {
            print(
                "Notilog monitoring was not started because "
                + "config.json could not be loaded: "
                + (
                    automationConfigurationStore.errorMessage
                        ?? "Unknown configuration error"
                )
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

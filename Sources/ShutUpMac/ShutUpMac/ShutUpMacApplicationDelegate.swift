import AppKit

@MainActor
final class ShutUpMacApplicationDelegate: NSObject, NSApplicationDelegate {
    private let notilogMonitoringController =
        NotilogMonitoringController()

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        notilogMonitoringController.start()
    }

    func applicationWillTerminate(
        _ notification: Notification
    ) {
        notilogMonitoringController.stop()
    }
}

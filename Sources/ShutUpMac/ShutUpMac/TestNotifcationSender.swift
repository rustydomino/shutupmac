import Foundation
import UserNotifications

final class TestNotificationSender: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TestNotificationSender()

    private override init() {
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func sendTestNotification() {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        print("Notification permission request failed: \(error)")
                        return
                    }

                    guard granted else {
                        print("Notification permission not granted")
                        return
                    }

                    self.postTestNotification()
                }

            case .authorized, .provisional, .ephemeral:
                self.postTestNotification()

            case .denied:
                print("Notification permission denied. Enable notifications for ShutUpMac in System Settings.")

            @unknown default:
                print("Unknown notification authorization status")
            }
        }
    }

    private func postTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "ShutUpMac Test Notification"
        content.body = "This is a test notification for ShutUpMac."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 1.0,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "shutupmac-test-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to send test notification: \(error)")
            } else {
                print("Sent test notification")
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

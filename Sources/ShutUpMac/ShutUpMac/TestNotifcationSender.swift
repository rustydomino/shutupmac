import Foundation
import UserNotifications

struct TestNotificationResult {
    let didSchedule: Bool
    let message: String
}

final class TestNotificationSender: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TestNotificationSender()

    private override init() {
        super.init()
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
    }

    func sendTestNotification() {
        sendTestNotificationResult { result in
            print(result.message)
        }
    }

    func sendTestNotificationResult(
        completion: @escaping (TestNotificationResult) -> Void
    ) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        self.finish(
                            TestNotificationResult(
                                didSchedule: false,
                                message: "Notification permission request failed: \(error.localizedDescription)"
                            ),
                            completion: completion
                        )
                        return
                    }

                    guard granted else {
                        self.finish(
                            TestNotificationResult(
                                didSchedule: false,
                                message: "Notification permission was not granted. Enable notifications for ShutUpMac in System Settings."
                            ),
                            completion: completion
                        )
                        return
                    }

                    self.postTestNotification(completion: completion)
                }

            case .authorized, .provisional, .ephemeral:
                self.postTestNotification(completion: completion)

            case .denied:
                self.finish(
                    TestNotificationResult(
                        didSchedule: false,
                        message: "Notifications are disabled for ShutUpMac. Enable notifications in System Settings to use test notifications."
                    ),
                    completion: completion
                )

            @unknown default:
                self.finish(
                    TestNotificationResult(
                        didSchedule: false,
                        message: "Unknown notification authorization status. Check ShutUpMac notification settings in System Settings."
                    ),
                    completion: completion
                )
            }
        }
    }

    private func postTestNotification(
        completion: @escaping (TestNotificationResult) -> Void
    ) {
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
                self.finish(
                    TestNotificationResult(
                        didSchedule: false,
                        message: "Failed to schedule test notification: \(error.localizedDescription)"
                    ),
                    completion: completion
                )
            } else {
                self.finish(
                    TestNotificationResult(
                        didSchedule: true,
                        message: "Test notification was scheduled."
                    ),
                    completion: completion
                )
            }
        }
    }

    private func finish(
        _ result: TestNotificationResult,
        completion: @escaping (TestNotificationResult) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
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

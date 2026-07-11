import Foundation
import UserNotifications

final class NotificationGenerator {
    private let center = UNUserNotificationCenter.current()

    func generateTestNotifications() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])

            guard granted else {
                print("Notification permission was denied.")
                return
            }

            for groupIndex in 1...3 {
                for notificationIndex in 1...3 {
                    let content = UNMutableNotificationContent()
                    content.title = "ShutUpMac Test Group \(groupIndex)"
                    content.subtitle = "Multiple group test"
                    content.body = "Notification \(notificationIndex) of 3 in group \(groupIndex)"
                    content.threadIdentifier = "shutupmac.test.group.\(groupIndex)"
                    content.sound = .default

                    let request = UNNotificationRequest(
                        identifier: "shutupmac.test.group.\(groupIndex).notification.\(notificationIndex).\(UUID().uuidString)",
                        content: content,
                        trigger: nil
                    )

                    try await center.add(request)

                    print("Sent group \(groupIndex), notification \(notificationIndex)")

                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }

            print("Generated 5 grouped test notifications.")
        } catch {
            print("Failed to generate notifications: \(error)")
        }
    }
}

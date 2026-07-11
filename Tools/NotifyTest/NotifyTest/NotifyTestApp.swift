import SwiftUI
import AppKit

@main
struct NotifyTestApp: App {

    init() {
        Task {
            let generator = NotificationGenerator()
            await generator.generateTestNotifications()

            // Give Notification Center a moment to receive everything.
            try? await Task.sleep(nanoseconds: 1_000_000_000)

//            await MainActor.run {
//                NSApplication.shared.terminate(nil)
//            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

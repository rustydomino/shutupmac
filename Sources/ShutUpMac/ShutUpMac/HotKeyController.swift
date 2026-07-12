import Foundation
import Carbon

final class HotKeyController {
    static let shared = HotKeyController()

    private var clearHotKeyRef: EventHotKeyRef?
    private var testNotificationHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private var isStarted = false

    private enum HotKeyID {
        static let clearNotifications: UInt32 = 1
        static let sendTestNotification: UInt32 = 2
    }

    private init() {}

    func start() {
        guard !isStarted else {
            return
        }

        guard AppPreferences.enableGlobalHotkeys else {
            print("Global hotkeys disabled")
            return
        }

        let eventCallback: EventHandlerUPP = { _, event, userData in
            guard let userData else {
                return noErr
            }

            let controller = Unmanaged<HotKeyController>
                .fromOpaque(userData)
                .takeUnretainedValue()

            controller.handleCarbonHotKeyEvent(event)

            return noErr
        }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            eventCallback,
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if installStatus != noErr {
            print("Failed to install hotkey event handler: \(installStatus)")
            return
        }

        let clearHotKey = AppPreferences.clearNotificationsHotKey
        let testHotKey = AppPreferences.testNotificationHotKey

        clearHotKeyRef = registerHotKey(
            clearHotKey,
            id: HotKeyID.clearNotifications,
            purpose: "clear notifications"
        )

        if testHotKey == clearHotKey {
            print("Test notification hotkey not registered because it duplicates clear notifications: \(testHotKey.displayString)")
        } else {
            testNotificationHotKeyRef = registerHotKey(
                testHotKey,
                id: HotKeyID.sendTestNotification,
                purpose: "send test notification"
            )
        }

        isStarted = true
    }

    func stop() {
        if let clearHotKeyRef {
            UnregisterEventHotKey(clearHotKeyRef)
            self.clearHotKeyRef = nil
        }

        if let testNotificationHotKeyRef {
            UnregisterEventHotKey(testNotificationHotKeyRef)
            self.testNotificationHotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }

        isStarted = false
    }

    func restart() {
        stop()

        if AppPreferences.enableGlobalHotkeys {
            start()
        }
    }

    private func registerHotKey(
        _ hotKey: HotKey,
        id: UInt32,
        purpose: String
    ) -> EventHotKeyRef? {
        guard hotKey.isValidGlobalShortcut else {
            print("Not registering invalid \(purpose) hotkey: \(hotKey.displayString)")
            return nil
        }

        var hotKeyRef: EventHotKeyRef?

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("SUMC"),
            id: id
        )

        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            print("Registered \(purpose) hotkey: \(hotKey.displayString)")
            return hotKeyRef
        }

        print("Failed to register \(purpose) hotkey \(hotKey.displayString): \(status)")
        return nil
    }

    private func handleCarbonHotKeyEvent(_ event: EventRef?) {
        guard let event else {
            return
        }

        var hotKeyID = EventHotKeyID()

        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            print("Could not read hotkey event parameter: \(status)")
            return
        }

        handleHotKey(id: hotKeyID.id)
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case HotKeyID.clearNotifications:
            NotificationClearer.clear()

        case HotKeyID.sendTestNotification:
            TestNotificationSender.shared.sendTestNotification()

        default:
            break
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0

        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }

        return result
    }
}

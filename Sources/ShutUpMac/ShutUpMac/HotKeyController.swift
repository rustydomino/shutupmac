import Foundation
import Carbon

final class HotKeyController {
    static let shared = HotKeyController()

    private var clearVisibleHotKeyRef: EventHotKeyRef?
    private var clearAllHotKeyRef: EventHotKeyRef?
    private var testNotificationHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private var isStarted = false

    private enum HotKeyID {
        static let clearVisibleNotifications: UInt32 = 1
        static let clearAllNotifications: UInt32 = 2
        static let sendTestNotification: UInt32 = 3
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

        var registeredHotKeys: [HotKey: String] = [:]

        clearVisibleHotKeyRef = registerHotKeyIfUnique(
            AppPreferences.clearVisibleNotificationsHotKey,
            id: HotKeyID.clearVisibleNotifications,
            purpose: "clear visible notifications",
            registeredHotKeys: &registeredHotKeys
        )

        clearAllHotKeyRef = registerHotKeyIfUnique(
            AppPreferences.clearAllNotificationsHotKey,
            id: HotKeyID.clearAllNotifications,
            purpose: "clear all notifications",
            registeredHotKeys: &registeredHotKeys
        )

        testNotificationHotKeyRef = registerHotKeyIfUnique(
            AppPreferences.testNotificationHotKey,
            id: HotKeyID.sendTestNotification,
            purpose: "send test notification",
            registeredHotKeys: &registeredHotKeys
        )

        isStarted = true
    }

    func stop() {
        if let clearVisibleHotKeyRef {
            UnregisterEventHotKey(clearVisibleHotKeyRef)
            self.clearVisibleHotKeyRef = nil
        }

        if let clearAllHotKeyRef {
            UnregisterEventHotKey(clearAllHotKeyRef)
            self.clearAllHotKeyRef = nil
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

    private func registerHotKeyIfUnique(
        _ hotKey: HotKey,
        id: UInt32,
        purpose: String,
        registeredHotKeys: inout [HotKey: String]
    ) -> EventHotKeyRef? {
        if let existingPurpose = registeredHotKeys[hotKey] {
            print("Not registering \(purpose) hotkey because it duplicates \(existingPurpose): \(hotKey.displayString)")
            return nil
        }

        let hotKeyRef = registerHotKey(
            hotKey,
            id: id,
            purpose: purpose
        )

        if hotKeyRef != nil {
            registeredHotKeys[hotKey] = purpose
        }

        return hotKeyRef
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
        case HotKeyID.clearVisibleNotifications:
            NotificationClearer.clearVisible()

        case HotKeyID.clearAllNotifications:
            NotificationClearer.clearAll()

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

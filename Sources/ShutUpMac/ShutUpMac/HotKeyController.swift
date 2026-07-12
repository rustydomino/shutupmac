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
        guard !isStarted else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else {
                    return noErr
                }

                let controller = Unmanaged<HotKeyController>
                    .fromOpaque(userData)
                    .takeUnretainedValue()

                controller.handleCarbonHotKeyEvent(event)

                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        guard installStatus == noErr else {
            print("Failed to install hotkey event handler: \(installStatus)")
            return
        }

        let modifiers = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)

        clearHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_D),
            modifiers: modifiers,
            id: HotKeyID.clearNotifications,
            name: "Control-Option-Command-D"
        )

        testNotificationHotKeyRef = registerHotKey(
            keyCode: UInt32(kVK_ANSI_S),
            modifiers: modifiers,
            id: HotKeyID.sendTestNotification,
            name: "Control-Option-Command-S"
        )

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

    private func registerHotKey(
        keyCode: UInt32,
        modifiers: UInt32,
        id: UInt32,
        name: String
    ) -> EventHotKeyRef? {
        var hotKeyRef: EventHotKeyRef?

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("SUMC"),
            id: id
        )

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            print("Failed to register global hotkey \(name): \(status)")
            return nil
        }

        print("Registered global hotkey: \(name)")
        return hotKeyRef
    }

    private func handleCarbonHotKeyEvent(_ event: EventRef?) {
        guard let event else { return }

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
            print("Could not read hotkey ID: \(status)")
            return
        }

        handleHotKey(id: hotKeyID.id)
    }

    private func handleHotKey(id: UInt32) {
        switch id {
        case HotKeyID.clearNotifications:
            print("GLOBAL HOTKEY PRESSED: Clear Notifications")

            DispatchQueue.main.async {
                NotificationClearer.clear()
            }

        case HotKeyID.sendTestNotification:
            print("GLOBAL HOTKEY PRESSED: Send Test Notification")

            DispatchQueue.main.async {
                TestNotificationSender.shared.sendTestNotification()
            }

        default:
            print("Unknown global hotkey ID: \(id)")
        }
    }
}

private func fourCharCode(_ string: String) -> OSType {
    var result: OSType = 0

    for scalar in string.unicodeScalars {
        result = (result << 8) + OSType(scalar.value)
    }

    return result
}

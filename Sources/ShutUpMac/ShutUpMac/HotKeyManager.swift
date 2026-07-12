import Foundation
import AppKit
import Carbon

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var didInstallHandler = false

    private let hotKeySignature = fourCharCode("SUMC")
    private let hotKeyID: UInt32 = 1

    private init() {}

    func registerHotKey() {
        installEventHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?

        let hotKeyIdentifier = EventHotKeyID(
            signature: hotKeySignature,
            id: hotKeyID
        )

        // ctrl + option + command
        let modifiers = UInt32(controlKey | optionKey | cmdKey)

        // N key
        let keyCode = UInt32(kVK_ANSI_N)

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyIdentifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            self.hotKeyRef = hotKeyRef
            print("Registered hotkey: ctrl-option-command-N")
        } else {
            print("Failed to register hotkey. OSStatus: \(status)")
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
            print("Unregistered hotkey")
        }
    }

    private func installEventHandlerIfNeeded() {
        guard !didInstallHandler else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, _ in
                guard let eventRef else {
                    return noErr
                }

                var hotKeyID = EventHotKeyID()

                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else {
                    return noErr
                }

                if hotKeyID.signature == fourCharCode("SUMC") && hotKeyID.id == 1 {
                    DispatchQueue.main.async {
                        print("Hotkey pressed: ctrl-option-command-N")
                        NotificationClearer.clear()
                    }
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        if status == noErr {
            didInstallHandler = true
            print("Installed hotkey event handler")
        } else {
            print("Failed to install hotkey event handler. OSStatus: \(status)")
        }
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0

    for scalar in string.unicodeScalars {
        result = (result << 8) + FourCharCode(scalar.value)
    }

    return result
}

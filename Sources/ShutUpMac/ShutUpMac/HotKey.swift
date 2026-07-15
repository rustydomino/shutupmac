import Foundation
import AppKit
import Carbon

struct HotKey: Equatable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyName: String

    static let standardModifiers =
        UInt32(controlKey) |
        UInt32(optionKey) |
        UInt32(cmdKey)

    static let defaultClearVisible = HotKey(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: standardModifiers,
        keyName: "V"
    )

    static let defaultClearAll = HotKey(
        keyCode: UInt32(kVK_ANSI_A),
        modifiers: standardModifiers,
        keyName: "A"
    )

    static let defaultTestNotification = HotKey(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: standardModifiers,
        keyName: "T"
    )

    // Legacy alias for older call sites.
    static let defaultClear = defaultClearAll

    var encodedString: String {
        "\(keyCode)|\(modifiers)|\(keyName)"
    }

    var displayString: String {
        var result = ""

        if hasModifier(UInt32(shiftKey)) {
            result += "⇧"
        }

        if hasModifier(UInt32(controlKey)) {
            result += "⌃"
        }

        if hasModifier(UInt32(optionKey)) {
            result += "⌥"
        }

        if hasModifier(UInt32(cmdKey)) {
            result += "⌘"
        }

        result += keyName

        return result
    }

    var isValidGlobalShortcut: Bool {
        primaryModifierCount >= 2
    }

    private var primaryModifierCount: Int {
        var count = 0

        if hasModifier(UInt32(controlKey)) {
            count += 1
        }

        if hasModifier(UInt32(optionKey)) {
            count += 1
        }

        if hasModifier(UInt32(cmdKey)) {
            count += 1
        }

        return count
    }

    private func hasModifier(_ modifier: UInt32) -> Bool {
        modifiers & modifier != 0
    }

    static func decode(_ value: String?) -> HotKey? {
        guard let value else {
            return nil
        }

        let parts = value.split(separator: "|", maxSplits: 2).map(String.init)

        guard parts.count == 3,
              let keyCode = UInt32(parts[0]),
              let modifiers = UInt32(parts[1])
        else {
            return nil
        }

        return HotKey(
            keyCode: keyCode,
            modifiers: modifiers,
            keyName: parts[2]
        )
    }

    static func from(event: NSEvent) -> HotKey? {
        guard let keyName = keyName(from: event) else {
            return nil
        }

        return HotKey(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers(from: event.modifierFlags),
            keyName: keyName
        )
    }

    private static func keyName(from event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers?.uppercased(),
              characters.count == 1
        else {
            return nil
        }

        let allowedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

        guard allowedCharacters.contains(characters) else {
            return nil
        }

        return characters
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)

        var carbonFlags: UInt32 = 0

        if deviceFlags.contains(.shift) {
            carbonFlags |= UInt32(shiftKey)
        }

        if deviceFlags.contains(.control) {
            carbonFlags |= UInt32(controlKey)
        }

        if deviceFlags.contains(.option) {
            carbonFlags |= UInt32(optionKey)
        }

        if deviceFlags.contains(.command) {
            carbonFlags |= UInt32(cmdKey)
        }

        return carbonFlags
    }
}

enum HotKeyAvailability {
    static func isAvailable(_ hotKey: HotKey) -> Bool {
        var hotKeyRef: EventHotKeyRef?

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("SUMT"),
            id: 999
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
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }

            return true
        }

        return false
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0

        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }

        return result
    }
}

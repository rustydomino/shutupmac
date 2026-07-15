import SwiftUI
import Carbon

private struct MenuKeyboardShortcut {
    let key: SwiftUI.KeyEquivalent
    let modifiers: SwiftUI.EventModifiers
}

extension HotKey {
    fileprivate var swiftUIMenuKeyboardShortcut: MenuKeyboardShortcut? {
        guard keyName.count == 1,
              let character = keyName.lowercased().first
        else {
            return nil
        }

        return MenuKeyboardShortcut(
            key: SwiftUI.KeyEquivalent(character),
            modifiers: swiftUIEventModifiers
        )
    }

    private var swiftUIEventModifiers: SwiftUI.EventModifiers {
        var result = SwiftUI.EventModifiers()

        if hasCarbonModifier(UInt32(shiftKey)) {
            result.insert(SwiftUI.EventModifiers.shift)
        }

        if hasCarbonModifier(UInt32(controlKey)) {
            result.insert(SwiftUI.EventModifiers.control)
        }

        if hasCarbonModifier(UInt32(optionKey)) {
            result.insert(SwiftUI.EventModifiers.option)
        }

        if hasCarbonModifier(UInt32(cmdKey)) {
            result.insert(SwiftUI.EventModifiers.command)
        }

        return result
    }

    private func hasCarbonModifier(_ modifier: UInt32) -> Bool {
        modifiers & modifier != 0
    }
}

extension View {
    @ViewBuilder
    func menuKeyboardShortcut(_ hotKey: HotKey?) -> some View {
        if let shortcut = hotKey?.swiftUIMenuKeyboardShortcut {
            self.keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
        } else {
            self
        }
    }
}

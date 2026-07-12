import Foundation
import Carbon

enum HotKeyChoice: String, CaseIterable, Identifiable {
    case disabled = "disabled"
    case controlOptionCommandD = "controlOptionCommandD"
    case controlOptionCommandS = "controlOptionCommandS"
    case controlOptionCommandN = "controlOptionCommandN"
    case controlOptionCommandK = "controlOptionCommandK"
    case controlOptionCommandM = "controlOptionCommandM"

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .disabled:
            return "Disabled"
        case .controlOptionCommandD:
            return "Ctrl-Option-Command-D"
        case .controlOptionCommandS:
            return "Ctrl-Option-Command-S"
        case .controlOptionCommandN:
            return "Ctrl-Option-Command-N"
        case .controlOptionCommandK:
            return "Ctrl-Option-Command-K"
        case .controlOptionCommandM:
            return "Ctrl-Option-Command-M"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .disabled:
            return nil
        case .controlOptionCommandD:
            return UInt32(kVK_ANSI_D)
        case .controlOptionCommandS:
            return UInt32(kVK_ANSI_S)
        case .controlOptionCommandN:
            return UInt32(kVK_ANSI_N)
        case .controlOptionCommandK:
            return UInt32(kVK_ANSI_K)
        case .controlOptionCommandM:
            return UInt32(kVK_ANSI_M)
        }
    }

    var modifiers: UInt32? {
        switch self {
        case .disabled:
            return nil
        default:
            return UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        }
    }
}

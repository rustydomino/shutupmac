import Combine
import SwiftUI

enum ShutUpMacTab: CaseIterable, Identifiable {
    case general
    case hotKeys
    case activity
    case rules

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .general:
            "General"

        case .hotKeys:
            "Hot Keys"

        case .activity:
            "Activity"

        case .rules:
            "Rules"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "gearshape"

        case .hotKeys:
            "keyboard"

        case .activity:
            "clock.arrow.circlepath"

        case .rules:
            "list.bullet.rectangle"
        }
    }
}

@MainActor
final class ShutUpMacNavigation: ObservableObject {
    @Published var selectedTab: ShutUpMacTab = .general
}

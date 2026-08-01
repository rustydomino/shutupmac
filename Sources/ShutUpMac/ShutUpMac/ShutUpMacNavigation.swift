import Combine
import Foundation
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

struct RuleEditorSeed:
    Equatable,
    Identifiable
{
    let id: UUID
    let name: String
    let app: String
    let titleContains: String?
    let subtitleContains: String?

    init(
        id: UUID = UUID(),
        name: String,
        app: String,
        titleContains: String?,
        subtitleContains: String?
    ) {
        self.id = id
        self.name = name
        self.app = app
        self.titleContains = titleContains
        self.subtitleContains = subtitleContains
    }
}

@MainActor
final class ShutUpMacNavigation: ObservableObject {
    @Published
    var selectedTab: ShutUpMacTab = .general

    @Published
    var pendingRuleSeed: RuleEditorSeed?

    func beginRuleCreation(
        from seed: RuleEditorSeed
    ) {
        pendingRuleSeed = seed
        selectedTab = .rules
    }
}

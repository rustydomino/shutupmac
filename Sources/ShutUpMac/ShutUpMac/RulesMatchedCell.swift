import SwiftUI

struct RulesMatchedCell: View {
    let matchedRules: [MatchedRuleSnapshot]

    @State private var isShowingDetails = false

    var body: some View {
        if matchedRules.isEmpty {
            Text("—")
                .foregroundStyle(.secondary)
        } else {
            Button(countLabel) {
                isShowingDetails.toggle()
            }
            .buttonStyle(.link)
            .popover(
                isPresented: $isShowingDetails,
                arrowEdge: .bottom
            ) {
                ruleDetails
            }
        }
    }

    private var ruleDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rules matched")
                    .font(.headline)

                ForEach(matchedRules) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(rule.name)
                            .fontWeight(.semibold)
                            .textSelection(.enabled)

                        if rule.actions.isEmpty {
                            Text("No actions configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(
                                rule.actions.indices,
                                id: \.self
                            ) { index in
                                let action = rule.actions[index]

                                Label(
                                    action.displayName,
                                    systemImage: iconName(
                                        for: action
                                    )
                                )
                                .font(.callout)
                            }
                        }
                    }

                    if rule.id != matchedRules.last?.id {
                        Divider()
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding()
        }
        .frame(
            minWidth: 320,
            idealWidth: 360,
            maxWidth: 420,
            minHeight: 100,
            maxHeight: 420
        )
    }

    private var countLabel: String {
        switch matchedRules.count {
        case 1:
            return "1 rule matched"

        default:
            return "\(matchedRules.count) rules matched"
        }
    }

    private func iconName(
        for action: MatchedRuleActionSnapshot
    ) -> String {
        switch action {
        case .dismissNotification:
            return "bell.slash"

        case .runCommand:
            return "terminal"

        case .diagnosticLog:
            return "ladybug"
        }
    }
}

import SwiftUI
import NotilogCore

struct RulesView: View {
    @ObservedObject
    var store: AutomationConfigurationStore

    @State private var selectedRuleID: UUID?

    private var rules: [AutomationRuleConfig] {
        store.configuration?.rules ?? []
    }

    private var selectedRule: AutomationRuleConfig? {
        guard let selectedRuleID else {
            return nil
        }

        return rules.first {
            $0.id == selectedRuleID
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(
                        systemName: "exclamationmark.triangle.fill"
                    )

                    Text(errorMessage)
                        .textSelection(.enabled)

                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.red)
                .padding(10)

                Divider()
            }

            if store.configuration == nil {
                ContentUnavailableView(
                    "Configuration Not Loaded",
                    systemImage: "doc.badge.gearshape",
                    description: Text(
                        "ShutUpMac could not load the rules configuration."
                    )
                )
            } else if rules.isEmpty {
                ContentUnavailableView(
                    "No Rules",
                    systemImage: "list.bullet.rectangle",
                    description: Text(
                        "No notification rules are currently configured."
                    )
                )
            } else {
                HSplitView {
                    ruleList

                    ruleDetail
                }
            }
        }
        .frame(
            minWidth: 700,
            minHeight: 420
        )

        .onAppear {
            if store.configuration == nil {
                _ = store.load()
            }

            repairSelection()
        }
        .onChange(of: rules.map(\.id)) { _, _ in
            repairSelection()
        }

    }

    private func repairSelection() {
        if let selectedRuleID,
           rules.contains(
               where: { rule in
                   rule.id == selectedRuleID
               }
           ) {
            return
        }

        selectedRuleID = rules.first?.id
    }

    private var ruleList: some View {
        List(selection: $selectedRuleID) {
            ForEach(rules, id: \.id) { rule in
                HStack(spacing: 8) {
                    Image(
                        systemName:
                            rule.isEnabled
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        rule.isEnabled
                        ? .primary
                        : .secondary
                    )
                    .accessibilityLabel(
                        rule.isEnabled
                        ? "Enabled"
                        : "Disabled"
                    )

                    Text(rule.name)
                        .lineLimit(1)
                        .foregroundStyle(
                            rule.isEnabled
                            ? .primary
                            : .secondary
                        )

                    Spacer()
                }
                .tag(rule.id)
            }
        }
        .frame(
            minWidth: 220,
            idealWidth: 260,
            maxWidth: 340
        )
    }

    @ViewBuilder
    private var ruleDetail: some View {
        if let selectedRule {
            RuleDetailView(rule: selectedRule)
        } else {
            ContentUnavailableView(
                "Select a Rule",
                systemImage: "list.bullet.rectangle",
                description: Text(
                    "Select a rule to view its match conditions and actions."
                )
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }
}

private struct RuleDetailView: View {
    let rule: AutomationRuleConfig

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: 20
            ) {
                HStack(alignment: .firstTextBaseline) {
                    Text(rule.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .textSelection(.enabled)

                    Spacer()

                    Label(
                        rule.isEnabled
                            ? "Enabled"
                            : "Disabled",
                        systemImage:
                            rule.isEnabled
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .foregroundStyle(
                        rule.isEnabled
                            ? .primary
                            : .secondary
                    )
                }

                GroupBox("Matches") {
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        if let value = rule.match.appEquals {
                            RulePropertyRow(
                                label: "App",
                                value: "is “\(value)”"
                            )
                        }

                        if let value = rule.match.appContains {
                            RulePropertyRow(
                                label: "App",
                                value: "contains “\(value)”"
                            )
                        }

                        if let value = rule.match.titleContains {
                            RulePropertyRow(
                                label: "Title",
                                value: "contains “\(value)”"
                            )
                        }

                        if let value = rule.match.subtitleContains {
                            RulePropertyRow(
                                label: "Subtitle",
                                value: "contains “\(value)”"
                            )
                        }

                        if let value = rule.match.bodyContains {
                            RulePropertyRow(
                                label: "Body",
                                value: "contains “\(value)”"
                            )
                        }

                        if let value = rule.match.anyTextContains {
                            RulePropertyRow(
                                label: "Any text",
                                value: "contains “\(value)”"
                            )
                        }

                        if !hasSpecificMatchCriteria {
                            Text("Any notification")
                                .foregroundStyle(.secondary)
                        }

                        Toggle(
                            "Case-sensitive matching",
                            isOn: .constant(
                                rule.match.caseSensitive ?? false
                            )
                        )
                        .toggleStyle(.checkbox)
                        .allowsHitTesting(false)

                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }

                if let exceptions = rule.exceptions,
                   !exceptions.isEmpty {

                    GroupBox("Except when") {
                        VStack(
                            alignment: .leading,
                            spacing: 10
                        ) {
                            ForEach(
                                Array(exceptions.enumerated()),
                                id: \.offset
                            ) { _, exception in
                                RulePropertyRow(
                                    label: exceptionFieldName(
                                        exception.field
                                    ),
                                    value:
                                        "contains “\(exception.contains)”"
                                )
                            }
                        }
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                }

                GroupBox("Actions") {
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        ForEach(
                            Array(rule.actions.enumerated()),
                            id: \.offset
                        ) { _, action in
                            Label(
                                actionSummary(action),
                                systemImage:
                                    actionSystemImage(action)
                            )
                            .textSelection(.enabled)
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        alignment: .leading
                    )
                }

                Spacer()
            }
            .padding(20)
        }
        .frame(
            minWidth: 420,
            maxWidth: .infinity,
            maxHeight: .infinity
        )
    }

    private var hasSpecificMatchCriteria: Bool {
        rule.match.eventTypes != nil
            || rule.match.appEquals != nil
            || rule.match.appContains != nil
            || rule.match.titleContains != nil
            || rule.match.subtitleContains != nil
            || rule.match.bodyContains != nil
            || rule.match.anyTextContains != nil
    }

    private func exceptionFieldName(
        _ field: NotificationExceptionField
    ) -> String {
        switch field {
        case .title:
            return "Title"

        case .subtitle:
            return "Subtitle"

        case .body:
            return "Body"
        }
    }

    private func actionSummary(
        _ action: NotificationActionConfig
    ) -> String {
        switch action.type {
        case "shutupmac_dismiss":
            return "Dismiss notification"

        case "dryRunLog", "dry_run_log":
            return "Log: \(action.message ?? "")"

        case "exec":
            let arguments =
                action.arguments?.joined(separator: " ")
                ?? ""

            return [
                action.command ?? "",
                arguments
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        default:
            return "Unknown action: \(action.type)"
        }
    }

    private func actionSystemImage(
        _ action: NotificationActionConfig
    ) -> String {
        switch action.type {
        case "shutupmac_dismiss":
            return "xmark.circle"

        case "dryRunLog", "dry_run_log":
            return "text.bubble"

        case "exec":
            return "terminal"

        default:
            return "questionmark.circle"
        }
    }
}

private struct RulePropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(
                    width: 100,
                    alignment: .leading
                )

            Text(value)
                .textSelection(.enabled)

            Spacer()
        }
    }
}

private extension AutomationRuleConfig {
    var isEnabled: Bool {
        enabled ?? true
    }
}

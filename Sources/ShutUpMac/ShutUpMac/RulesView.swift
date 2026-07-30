import SwiftUI
import NotilogCore

struct RulesView: View {
    @ObservedObject
    var store: AutomationConfigurationStore

    let saveAutomationConfiguration:
        (AutomationConfig) -> Void

    @State private var selectedRuleID: UUID?
    @State private var isPresentingRuleEditor = false

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

        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingRuleEditor = true
                } label: {
                    Label(
                        "Add Rule",
                        systemImage: "plus"
                    )
                }
                .help("Add rule")
                .disabled(store.configuration == nil)
            }
        }
        .sheet(isPresented: $isPresentingRuleEditor) {
            RuleEditorView { rule in
                guard let configuration =
                        store.configuration else {
                    return
                }

                let candidate = configuration.addingRule(rule)

                saveAutomationConfiguration(candidate)
                selectedRuleID = rule.id
            }
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

    private func toggleRuleEnabled(
        _ rule: AutomationRuleConfig
    ) {
        guard !rule.usesAdvancedConfiguration,
            let configuration = store.configuration else {
            return
        }

        let candidate = configuration.settingRuleEnabled(
            id: rule.id,
            enabled: !rule.isEnabled
        )

        saveAutomationConfiguration(candidate)
    }

    private var ruleList: some View {
        List(selection: $selectedRuleID) {
            ForEach(rules, id: \.id) { rule in
                HStack(spacing: 8) {
                    if rule.usesAdvancedConfiguration {
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
                    } else {
                        Button {
                            toggleRuleEnabled(rule)
                        } label: {
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
                        }
                        .buttonStyle(.plain)
                        .help(
                            rule.isEnabled
                                ? "Disable rule"
                                : "Enable rule"
                        )
                        .accessibilityLabel(
                            rule.isEnabled
                                ? "Disable rule"
                                : "Enable rule"
                        )
                    }

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

private enum TextMatchOperator:
    String,
    CaseIterable,
    Identifiable {
    case equals
    case contains

    var id: Self {
        self
    }

    var label: String {
        switch self {
        case .equals:
            return "is exactly"

        case .contains:
            return "contains"
        }
    }
}

private struct RuleEditorView: View {
    @Environment(\.dismiss)
    private var dismiss

    let onAdd: (AutomationRuleConfig) -> Void

    @State private var name = ""
    @State private var isEnabled = true

    @State private var app = ""

    @State private var titleOperator:
        TextMatchOperator = .contains

    @State private var title = ""

    @State private var subtitleOperator:
        TextMatchOperator = .contains

    @State private var subtitle = ""

    @State private var bodyOperator:
        TextMatchOperator = .contains

    @State private var bodyText = ""

    @State private var isCaseSensitive = false

    private var trimmedName: String {
        trimmed(name)
    }

    private var hasMatchCondition: Bool {
        [
            app,
            title,
            subtitle,
            bodyText
        ]
        .contains { !trimmed($0).isEmpty }
    }

    private var canAddRule: Bool {
        !trimmedName.isEmpty && hasMatchCondition
    }

    private var candidateRule: AutomationRuleConfig {
        AutomationRuleConfig(
            id: UUID(),
            name: trimmedName,
            enabled: isEnabled,
            match: NotificationMatchConfig(
                eventTypes: [.appeared],
                appEquals: optionalText(app),
                titleEquals:
                    titleOperator == .equals
                    ? optionalText(title)
                    : nil,
                titleContains:
                    titleOperator == .contains
                    ? optionalText(title)
                    : nil,
                subtitleEquals:
                    subtitleOperator == .equals
                    ? optionalText(subtitle)
                    : nil,
                subtitleContains:
                    subtitleOperator == .contains
                    ? optionalText(subtitle)
                    : nil,
                bodyEquals:
                    bodyOperator == .equals
                    ? optionalText(bodyText)
                    : nil,
                bodyContains:
                    bodyOperator == .contains
                    ? optionalText(bodyText)
                    : nil,
                caseSensitive: isCaseSensitive
            ),
            actions: [
                NotificationActionConfig(
                    type: "shutupmac_dismiss"
                )
            ]
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Rule") {
                    TextField(
                        "Name",
                        text: $name,
                        prompt: Text("Rule name")
                    )

                    Toggle(
                        "Enabled",
                        isOn: $isEnabled
                    )
                }

                Section("Matches") {
                    LabeledContent("App") {
                        TextField(
                            "App",
                            text: $app,
                            prompt: Text(
                                "Exact app name"
                            )
                        )
                    }

                    LabeledContent("Title") {
                        HStack {
                            operatorPicker(
                                selection:
                                    $titleOperator,
                                accessibilityLabel:
                                    "Title match operator"
                            )

                            TextField(
                                "Title",
                                text: $title,
                                prompt: Text(
                                    "Title text"
                                )
                            )
                        }
                    }

                    LabeledContent("Subtitle") {
                        HStack {
                            operatorPicker(
                                selection:
                                    $subtitleOperator,
                                accessibilityLabel:
                                    "Subtitle match operator"
                            )

                            TextField(
                                "Subtitle",
                                text: $subtitle,
                                prompt: Text(
                                    "Subtitle text"
                                )
                            )
                        }
                    }

                    LabeledContent("Body") {
                        HStack {
                            operatorPicker(
                                selection:
                                    $bodyOperator,
                                accessibilityLabel:
                                    "Body match operator"
                            )

                            TextField(
                                "Body",
                                text: $bodyText,
                                prompt: Text(
                                    "Body text"
                                )
                            )
                        }
                    }

                    Toggle(
                        "Case-sensitive matching",
                        isOn: $isCaseSensitive
                    )
                    .toggleStyle(.checkbox)
                }

                Section {
                    Text(
                        "App names are matched exactly. "
                        + "Empty match fields are ignored."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Add") {
                    onAdd(candidateRule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAddRule)
            }
            .padding()
        }
        .frame(
            width: 620,
            height: 520
        )
    }

    private func optionalText(
        _ value: String
    ) -> String? {
        let value = trimmed(value)

        return value.isEmpty
            ? nil
            : value
    }

    private func trimmed(
        _ value: String
    ) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    private func operatorPicker(
        selection: Binding<TextMatchOperator>,
        accessibilityLabel: String
    ) -> some View {
        Picker(
            accessibilityLabel,
            selection: selection
        ) {
            ForEach(
                TextMatchOperator.allCases
            ) { matchOperator in
                Text(matchOperator.label)
                    .tag(matchOperator)
            }
        }
        .labelsHidden()
        .frame(width: 110)
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

                if rule.usesAdvancedEventMatching {
                    AdvancedRuleNotice(
                        title: "Advanced event matching",
                        message:
                            "This rule matches on events other than "
                            + "notification appearance, which are not "
                            + "supported by the Rules Editor."
                    )
                }

                if rule.usesAdvancedFieldMatching {
                    AdvancedRuleNotice(
                        title: "Advanced field matching",
                        message:
                            "This rule uses match fields or "
                            + "operators that are not supported "
                            + "by the Rules Editor."
                    )
                }

                if rule.usesAdvancedActions {
                    AdvancedRuleNotice(
                        title: "Advanced actions",
                        message:
                            "This rule uses advanced actions that "
                            + "are not supported by the Rules Editor."
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

                        if let value = rule.match.titleEquals {
                            RulePropertyRow(
                                label: "Title",
                                value: "is “\(value)”"
                            )
                        }

                        if let value = rule.match.titleContains {
                            RulePropertyRow(
                                label: "Title",
                                value: "contains “\(value)”"
                            )
                        }

                        if let value = rule.match.subtitleEquals {
                            RulePropertyRow(
                                label: "Subtitle",
                                value: "is “\(value)”"
                            )
                        }

                        if let value = rule.match.subtitleContains {
                            RulePropertyRow(
                                label: "Subtitle",
                                value: "contains “\(value)”"
                            )
                        }

                        if let value = rule.match.bodyEquals {
                            RulePropertyRow(
                                label: "Body",
                                value: "is “\(value)”"
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

                if rule.usesAdvancedActions {
                    GroupBox("Advanced actions") {
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
            || rule.match.titleEquals != nil
            || rule.match.titleContains != nil
            || rule.match.subtitleEquals != nil
            || rule.match.subtitleContains != nil
            || rule.match.bodyEquals != nil
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

private struct AdvancedRuleNotice: View {
    let title: String
    let message: String

    var body: some View {
        GroupBox(title) {
            HStack(
                alignment: .top,
                spacing: 10
            ) {
                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)

                Text(message)
                    .foregroundStyle(.secondary)
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Spacer()
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
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

    var usesAdvancedConfiguration: Bool {
        usesAdvancedEventMatching
            || usesAdvancedFieldMatching
            || usesAdvancedActions
    }

    var usesAdvancedEventMatching: Bool {
        match.eventTypes != [.appeared]
    }

    var usesAdvancedFieldMatching: Bool {
        match.appContains != nil
            || match.anyTextContains != nil
            || hasBothOperators(
                equals: match.titleEquals,
                contains: match.titleContains
            )
            || hasBothOperators(
                equals: match.subtitleEquals,
                contains: match.subtitleContains
            )
            || hasBothOperators(
                equals: match.bodyEquals,
                contains: match.bodyContains
            )
    }

    private func hasBothOperators(
        equals: String?,
        contains: String?
    ) -> Bool {
        equals != nil && contains != nil
    }

    var usesAdvancedActions: Bool {
        guard actions.count == 1,
              let action = actions.first else {
            return true
        }

        guard action.type == "shutupmac_dismiss" else {
            return true
        }

        return action.command != nil
            || action.message != nil
            || !(action.arguments ?? []).isEmpty
    }
}

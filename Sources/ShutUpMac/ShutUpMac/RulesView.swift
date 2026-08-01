import NotilogCore
import SwiftUI

private enum PendingRuleNavigation {
    case select(UUID?)
    case createNew
    case createFromSeed(RuleEditorSeed)
}

struct RulesView: View {
    
    @ObservedObject
    var navigation: ShutUpMacNavigation    

    @ObservedObject
    var store: AutomationConfigurationStore

    let saveAutomationConfiguration:
        (AutomationConfig) -> Void

    let setNotilogRulesAutoDismissEnabled:
        (Bool) -> Void

    @AppStorage(
        PreferenceKeys.notilogRulesAutoDismissEnabled
    )
    private var notilogRulesAutoDismissEnabled = true

    @State private var selectedRuleID: UUID?

    @State private var isCreatingRule = false

    @State
    private var ruleCreationSeed:
        RuleEditorSeed?

    @State private var editorRevision = UUID()

    @State
    private var hasUnsavedEditorChanges = false

    @State
    private var pendingNavigation:
        PendingRuleNavigation?

    @State
    private var isPresentingDiscardAlert = false

    @State private var rulePendingDeletion:
        AutomationRuleConfig?
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

            VStack(
                alignment: .leading,
                spacing: 6
            ) {
                Toggle(
                    "Enable rules-based auto-dismiss",
                    isOn:
                        $notilogRulesAutoDismissEnabled
                )

                Text(
                    "When disabled, rules remain configured "
                        + "but do not dismiss notifications."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()

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
            } else if rules.isEmpty && !isCreatingRule {
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

        Divider()

        rulesActionBar

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
            consumePendingRuleSeed()
        }
        .onChange(of: rules.map(\.id)) { _, _ in
            repairSelection()
        }
       .onChange(
            of: navigation.pendingRuleSeed?.id
        ) { _, _ in
            consumePendingRuleSeed()
        }
        .onChange(
            of: notilogRulesAutoDismissEnabled
        ) { _, enabled in
            setNotilogRulesAutoDismissEnabled(
                enabled
            )
        }
        .confirmationDialog(
            "Delete Rule?",
            isPresented: Binding(
                get: {
                    rulePendingDeletion != nil
                },
                set: { isPresented in
                    if !isPresented {
                        rulePendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: rulePendingDeletion
        ) { rule in
            Button(
                "Delete “\(rule.name)”",
                role: .destructive
            ) {
                deleteRule(rule)
                rulePendingDeletion = nil
            }

            Button("Cancel", role: .cancel) {
                if let destination =
                    pendingNavigation
                {
                    clearPendingRuleSeed(
                        for: destination
                    )
                }

                pendingNavigation = nil
            }
        } message: { _ in
            Text("This action cannot be undone.")
        }
        .alert(
            "Discard Unsaved Changes?",
            isPresented:
                $isPresentingDiscardAlert
        ) {
            Button("Cancel", role: .cancel) {
                pendingNavigation = nil
            }

            Button(
                "Discard Changes",
                role: .destructive
            ) {
                guard let destination =
                    pendingNavigation
                else {
                    return
                }

                pendingNavigation = nil
                applyNavigation(destination)
                clearPendingRuleSeed(
                    for: destination
                )
            }
        } message: {
            Text(
                "Your unsaved rule changes will be lost."
            )
        }
    }

    private var rulesActionBar: some View {
        HStack(spacing: 12) {
            ControlGroup {
                Button {
                    requestNavigation(
                        to: .createNew
                    )
                } label: {
                    Label(
                        "Add Rule",
                        systemImage: "plus"
                    )
                }
                .help("Add rule")
                .disabled(store.configuration == nil)

                Button(role: .destructive) {
                    guard let selectedRule,
                          !selectedRule
                          .usesAdvancedConfiguration
                    else {
                        return
                    }

                    rulePendingDeletion = selectedRule
                } label: {
                    Label(
                        "Delete Rule",
                        systemImage: "minus"
                    )
                }
                .help("Delete selected rule")
                .disabled(
                    isCreatingRule
                        || selectedRule == nil
                        || selectedRule?
                        .usesAdvancedConfiguration == true
                )
            }
            .labelStyle(.iconOnly)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func repairSelection() {
        if let selectedRuleID,
           rules.contains(
               where: { rule in
                   rule.id == selectedRuleID
               }
           )
        {
            return
        }

        selectedRuleID = rules.first?.id
    }

    private func toggleRuleEnabled(
        _ rule: AutomationRuleConfig
    ) {
        guard !rule.usesAdvancedConfiguration,
              let configuration = store.configuration
        else {
            return
        }

        let candidate = configuration.settingRuleEnabled(
            id: rule.id,
            enabled: !rule.isEnabled
        )

        saveAutomationConfiguration(candidate)
    }

    private func deleteRule(
        _ rule: AutomationRuleConfig
    ) {
        guard !rule.usesAdvancedConfiguration,
              let configuration = store.configuration
        else {
            return
        }

        let candidate = configuration.removingRule(
            id: rule.id
        )

        selectedRuleID = nil
        saveAutomationConfiguration(candidate)
    }

    private func consumePendingRuleSeed() {
        guard let seed =
            navigation.pendingRuleSeed
        else {
            return
        }

        if case let .createFromSeed(pendingSeed) =
            pendingNavigation,
           pendingSeed.id == seed.id
        {
            return
        }

        requestNavigation(
            to: .createFromSeed(seed)
        )
    }

    private func clearPendingRuleSeed(
        for destination: PendingRuleNavigation
    ) {
        guard case let .createFromSeed(seed) =
            destination,
              navigation.pendingRuleSeed?.id ==
              seed.id
        else {
            return
        }

        navigation.pendingRuleSeed = nil
    }

    private func requestNavigation(
        to destination: PendingRuleNavigation
    ) {
        guard hasUnsavedEditorChanges else {
            applyNavigation(destination)
            clearPendingRuleSeed(
                for: destination
            )
            return
        }

        pendingNavigation = destination
        isPresentingDiscardAlert = true
    }

    private func applyNavigation(
        _ destination: PendingRuleNavigation
    ) {
        hasUnsavedEditorChanges = false
        editorRevision = UUID()

        switch destination {
        case let .select(ruleID):
            ruleCreationSeed = nil
            isCreatingRule = false
            selectedRuleID = ruleID

        case .createNew:
            ruleCreationSeed = nil
            selectedRuleID = nil
            isCreatingRule = true

        case let .createFromSeed(seed):
            ruleCreationSeed = seed
            selectedRuleID = nil
            isCreatingRule = true
        }
    }

    private var ruleSelection: Binding<UUID?> {
        Binding(
            get: {
                selectedRuleID
            },
            set: { newSelection in
                guard isCreatingRule
                        || newSelection != selectedRuleID
                else {
                    return
                }

                requestNavigation(
                    to: .select(newSelection)
                )
            }
        )
    }

    private var ruleList: some View {
        List(selection: ruleSelection) {
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
                                ? Color.primary
                                : Color.secondary
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
                                    ? Color.primary
                                    : Color.secondary
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
                        .truncationMode(.tail)
                        .foregroundStyle(
                            rule.isEnabled
                                ? Color.primary
                                : Color.secondary
                        )

                    Spacer(minLength: 8)

                    if rule.usesAdvancedConfiguration {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Advanced rule; read only")
                            .accessibilityLabel(
                                "Advanced rule, read only"
                            )
                    }
                }
                .padding(.vertical, 2)               
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
        if isCreatingRule {
            RuleEditorView(
                rule: nil,
                seed: ruleCreationSeed,
                onDirtyChange: { hasChanges in
                    hasUnsavedEditorChanges = hasChanges
                },
                onCancel: {
                    hasUnsavedEditorChanges = false
                    ruleCreationSeed = nil
                    isCreatingRule = false
                    repairSelection()
                },
                onSave: { rule in
                    guard let configuration =
                        store.configuration
                    else {
                        return
                    }

                    let candidate =
                        configuration.addingRule(rule)

                    saveAutomationConfiguration(candidate)

                    hasUnsavedEditorChanges = false
                    ruleCreationSeed = nil
                    selectedRuleID = rule.id
                    isCreatingRule = false
                    editorRevision = UUID()
                }
            )
            .id(
                "new-rule-"
                    + (
                        ruleCreationSeed?
                            .id.uuidString
                            ?? "blank"
                    )
                    + "-"
                    + editorRevision.uuidString
            )
        } else if let selectedRule {
            if selectedRule.usesAdvancedConfiguration {
                RuleDetailView(rule: selectedRule)
            } else {
                RuleEditorView(
                    rule: selectedRule,
                    onDirtyChange: { hasChanges in
                        hasUnsavedEditorChanges = hasChanges
                    },
                    onCancel: {
                        hasUnsavedEditorChanges = false
                        editorRevision = UUID()
                    },
                    onSave: { rule in
                        guard let configuration =
                            store.configuration
                        else {
                            return
                        }

                        let candidate =
                            configuration.replacingRule(rule)

                        saveAutomationConfiguration(candidate)
                        
                        hasUnsavedEditorChanges = false
                        selectedRuleID = rule.id
                    }
                )
                .id(
                    "rule-\(selectedRule.id.uuidString)"
                        + "-\(editorRevision.uuidString)"
                )
            }
        } else {
            ContentUnavailableView(
                "Select a Rule",
                systemImage: "list.bullet.rectangle",
                description: Text(
                    "Select a rule to edit it."
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
    Identifiable
{
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

private struct RuleExceptionDraft:
    Identifiable
{
    let id: UUID
    var field: NotificationExceptionField
    var text: String

    init(
        id: UUID = UUID(),
        field: NotificationExceptionField,
        text: String
    ) {
        self.id = id
        self.field = field
        self.text = text
    }
}

private struct RuleEditorExceptionSnapshot:
    Equatable
{
    let field: String
    let text: String
}

private struct RuleEditorSnapshot:
    Equatable
{
    let name: String
    let isEnabled: Bool

    let appEquals: String?

    let titleEquals: String?
    let titleContains: String?

    let subtitleEquals: String?
    let subtitleContains: String?

    let bodyEquals: String?
    let bodyContains: String?

    let isCaseSensitive: Bool

    let exceptions:
        [RuleEditorExceptionSnapshot]

    static let empty = RuleEditorSnapshot(
        name: "",
        isEnabled: true,
        appEquals: nil,
        titleEquals: nil,
        titleContains: nil,
        subtitleEquals: nil,
        subtitleContains: nil,
        bodyEquals: nil,
        bodyContains: nil,
        isCaseSensitive: false,
        exceptions: []
    )

    static func make(
        from rule: AutomationRuleConfig?
    ) -> RuleEditorSnapshot {
        guard let rule else {
            return .empty
        }

        return RuleEditorSnapshot(
            name:
                normalizedText(rule.name) ?? "",
            isEnabled:
                rule.enabled ?? true,
            appEquals:
                normalizedText(
                    rule.match.appEquals
                ),
            titleEquals:
                normalizedText(
                    rule.match.titleEquals
                ),
            titleContains:
                normalizedText(
                    rule.match.titleContains
                ),
            subtitleEquals:
                normalizedText(
                    rule.match.subtitleEquals
                ),
            subtitleContains:
                normalizedText(
                    rule.match.subtitleContains
                ),
            bodyEquals:
                normalizedText(
                    rule.match.bodyEquals
                ),
            bodyContains:
                normalizedText(
                    rule.match.bodyContains
                ),
            isCaseSensitive:
                rule.match.caseSensitive ?? false,
            exceptions:
                (rule.exceptions ?? []).compactMap {
                    exception in

                    guard let text =
                        normalizedText(
                            exception.contains
                        )
                    else {
                        return nil
                    }

                    return RuleEditorExceptionSnapshot(
                        field:
                            exception.field.rawValue,
                        text: text
                    )
                }
        )
    }

    private static func normalizedText(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let normalized =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return normalized.isEmpty
            ? nil
            : normalized
    }
}

private struct RuleEditorView: View {
    private let ruleID: UUID
    private let isEditing: Bool

    @State
    private var initialSnapshot:
        RuleEditorSnapshot

    let onDirtyChange: (Bool) -> Void
    let onCancel: () -> Void
    let onSave: (AutomationRuleConfig) -> Void

    @State private var name: String
    @State private var isEnabled: Bool

    @State private var app: String

    @State private var titleOperator:
        TextMatchOperator

    @State private var title: String

    @State private var subtitleOperator:
        TextMatchOperator

    @State private var subtitle: String

    @State private var bodyOperator:
        TextMatchOperator

    @State private var bodyText: String

    @State private var isCaseSensitive: Bool

    @State private var exceptionDrafts:
        [RuleExceptionDraft]

    init(
        rule: AutomationRuleConfig? = nil,
        seed: RuleEditorSeed? = nil,
        onDirtyChange:
            @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void,
        onSave: @escaping (
            AutomationRuleConfig
        ) -> Void
    ) {
        ruleID =
            rule?.id
                ?? seed?.id
                ?? UUID()
        isEditing = rule != nil
        self.onDirtyChange = onDirtyChange
        self.onCancel = onCancel
        self.onSave = onSave

        _initialSnapshot = State(
            initialValue:
                RuleEditorSnapshot.make(
                    from: rule
                )
        )

        let titleMatch = Self.editorMatch(
            equals: rule?.match.titleEquals,
            contains:
                rule?.match.titleContains
                    ?? seed?.titleContains
        )

        let subtitleMatch = Self.editorMatch(
            equals: rule?.match.subtitleEquals,
            contains:
                rule?.match.subtitleContains
                    ?? seed?.subtitleContains
        )

        let bodyMatch = Self.editorMatch(
            equals: rule?.match.bodyEquals,
            contains: rule?.match.bodyContains
        )

        _name = State(
            initialValue:
                rule?.name
                    ?? seed?.name
                    ?? ""
        )

        _isEnabled = State(
            initialValue: rule?.enabled ?? true
        )

        _app = State(
            initialValue:
                rule?.match.appEquals
                    ?? seed?.app
                    ?? ""
        )

        _titleOperator = State(
            initialValue: titleMatch.operator
        )

        _title = State(
            initialValue: titleMatch.text
        )

        _subtitleOperator = State(
            initialValue: subtitleMatch.operator
        )

        _subtitle = State(
            initialValue: subtitleMatch.text
        )

        _bodyOperator = State(
            initialValue: bodyMatch.operator
        )

        _bodyText = State(
            initialValue: bodyMatch.text
        )

        _isCaseSensitive = State(
            initialValue:
            rule?.match.caseSensitive ?? false
        )

        _exceptionDrafts = State(
            initialValue:
            (rule?.exceptions ?? []).map {
                RuleExceptionDraft(
                    field: $0.field,
                    text: $0.contains
                )
            }
        )
    }

    private var trimmedName: String {
        trimmed(name)
    }

    private var hasMatchCondition: Bool {
        [
            app,
            title,
            subtitle,
            bodyText,
        ]
        .contains { !trimmed($0).isEmpty }
    }

    private var canAddRule: Bool {
        !trimmedName.isEmpty && hasMatchCondition
    }

    private var hasChanges: Bool {
        RuleEditorSnapshot.make(
            from: candidateRule
        ) != initialSnapshot
    }

    private var canSubmitRule: Bool {
        canAddRule
            && (!isEditing || hasChanges)
    }

    private var candidateExceptions:
        [NotificationExceptionConfig]?
    {
        let exceptions = exceptionDrafts.compactMap {
            draft -> NotificationExceptionConfig? in
            guard let text = optionalText(draft.text) else {
                return nil
            }

            return NotificationExceptionConfig(
                field: draft.field,
                contains: text
            )
        }

        return exceptions.isEmpty
            ? nil
            : exceptions
    }

    private var candidateRule: AutomationRuleConfig {
        AutomationRuleConfig(
            id: ruleID,
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
            exceptions: candidateExceptions,
            actions: [
                NotificationActionConfig(
                    type: "shutupmac_dismiss"
                ),
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

                Section("Except when") {
                    if exceptionDrafts.isEmpty {
                        Text("No exceptions")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($exceptionDrafts) { $draft in
                        HStack {
                            Picker(
                                "Field",
                                selection:
                                    exceptionFieldBinding(
                                        for: $draft
                                    )
                            ) {
                                Text("Title")
                                    .tag("title")

                                Text("Subtitle")
                                    .tag("subtitle")

                                Text("Body")
                                    .tag("body")
                            }
                            .labelsHidden()
                            .frame(width: 100)

                            TextField(
                                "Exception text",
                                text: $draft.text,
                                prompt: Text("Text to ignore")
                            )

                            Button {
                                removeException(
                                    id: draft.id
                                )
                            } label: {
                                Image(
                                    systemName: "minus.circle"
                                )
                            }
                            .buttonStyle(.plain)
                            .help("Remove exception")
                            .accessibilityLabel(
                                "Remove exception"
                            )
                        }
                    }

                    Button {
                        exceptionDrafts.append(
                            RuleExceptionDraft(
                                field: .title,
                                text: ""
                            )
                        )
                    } label: {
                        Label(
                            "Add Exception",
                            systemImage: "plus"
                        )
                    }

                    Text(
                        "Any matching exception prevents this "
                        + "rule from dismissing the notification. "
                        + "Exceptions use contains matching and "
                        + "the rule’s case-sensitivity setting."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Button(
                    isEditing
                        ? "Revert"
                        : "Cancel New Rule"
                ) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(
                    isEditing
                        ? "Save Rule"
                        : "Add Rule"
                ) {
                    let rule = candidateRule

                    onSave(rule)

                    initialSnapshot =
                        RuleEditorSnapshot.make(
                            from: rule
                        )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmitRule)
            }
            .padding()
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .onAppear {
            onDirtyChange(hasChanges)
        }
        .onChange(of: hasChanges) { _, hasChanges in
            onDirtyChange(hasChanges)
        }
    }

    private static func editorMatch(
        equals: String?,
        contains: String?
    ) -> (
        operator: TextMatchOperator,
        text: String
    ) {
        if let equals {
            return (
                operator: .equals,
                text: equals
            )
        }

        return (
            operator: .contains,
            text: contains ?? ""
        )
    }

    private func exceptionFieldBinding(
        for draft: Binding<RuleExceptionDraft>
    ) -> Binding<String> {
        Binding(
            get: {
                draft.wrappedValue
                    .field
                    .rawValue
            },
            set: { rawValue in
                guard let field =
                        NotificationExceptionField(
                            rawValue: rawValue
                        ) else {
                    return
                }

                draft.wrappedValue.field = field
            }
        )
    }

    private func removeException(
        id: UUID
    ) {
        exceptionDrafts.removeAll {
            $0.id == id
        }
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
                   !exceptions.isEmpty
                {
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
                arguments,
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
              let action = actions.first
        else {
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

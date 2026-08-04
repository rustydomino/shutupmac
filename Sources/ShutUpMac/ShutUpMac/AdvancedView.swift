import Foundation
import NotilogCore
import SwiftUI

struct AdvancedView: View {
    let requestDatabaseStatistics:
        (
            @escaping @MainActor @Sendable (
                DatabaseStatisticsResult
            ) -> Void
        ) -> Void

    let resetActivityDatabase:
        (
            @escaping @MainActor @Sendable (
                ActivityDatabaseResetResult
            ) -> Void
        ) -> Void

    let updateRetentionLimits:
        (
            Int,
            Int,
            @escaping @MainActor @Sendable (
                RetentionLimitsUpdateResult
            ) -> Void
        ) -> Void

    init(
        initialRetentionConfiguration:
            RetentionConfiguration = .defaults,
        requestDatabaseStatistics: @escaping (
            @escaping @MainActor @Sendable (
                DatabaseStatisticsResult
            ) -> Void
        ) -> Void,
        resetActivityDatabase: @escaping (
            @escaping @MainActor @Sendable (
                ActivityDatabaseResetResult
            ) -> Void
        ) -> Void,
        updateRetentionLimits: @escaping (
            Int,
            Int,
            @escaping @MainActor @Sendable (
                RetentionLimitsUpdateResult
            ) -> Void
        ) -> Void
    ) {
        self.requestDatabaseStatistics =
            requestDatabaseStatistics

        self.resetActivityDatabase =
            resetActivityDatabase

        self.updateRetentionLimits =
            updateRetentionLimits

        _appliedRetentionConfiguration =
            State(
                initialValue:
                    initialRetentionConfiguration
            )

        _notificationEventLimitText =
            State(
                initialValue:
                    initialRetentionConfiguration
                        .notificationEventLimit
                        .formatted()
            )

        _actionRunLimitText =
            State(
                initialValue:
                    initialRetentionConfiguration
                        .actionRunLimit
                        .formatted()
            )
    }

    @State private var statistics:
        NotificationStoreStatistics?

    @State private var errorMessage: String?
    @State private var hasLoadedStatistics = false
    @State private var isLoading = false

    @State private var isShowingResetConfirmation = false
    @State private var isResettingDatabase = false
    @State private var resetErrorMessage: String?

    @State private var appliedRetentionConfiguration:
        RetentionConfiguration

    @State private var notificationEventLimitText:
        String

    @State private var actionRunLimitText:
        String

    @State private var isApplyingRetentionLimits = false
    @State private var retentionErrorMessage: String?

    private var databaseFileURL: URL {
        NotilogRuntimePaths
            .legacyNotilogDefault()
            .database
    }

    private var displayedDatabaseFilePath: String {
        (databaseFileURL.path as NSString)
            .abbreviatingWithTildeInPath
    }
    
    private var configFileURL: URL {
        NotilogRuntimePaths
            .legacyNotilogDefault()
            .config
    }

    private var displayedConfigFilePath: String {
        (configFileURL.path as NSString)
            .abbreviatingWithTildeInPath
    }

    private func historyRangeText(
        for statistics: NotificationStoreStatistics
    ) -> String {
        guard
            let oldest =
                statistics.oldestNotificationEventDate,
            let newest =
                statistics.newestNotificationEventDate
        else {
            return "No recorded activity"
        }

        let oldestText = oldest.formatted(
            date: .abbreviated,
            time: .omitted
        )

        let newestText = newest.formatted(
            date: .abbreviated,
            time: .omitted
        )

        if Calendar.current.isDate(
            oldest,
            inSameDayAs: newest
        ) {
            return oldestText
        }

        return oldestText + " – " + newestText
    }

    private func databaseStorageText(
        _ byteCount: Int64
    ) -> String {
        ByteCountFormatter.string(
            fromByteCount: byteCount,
            countStyle: .file
        )
    }
    
    private var parsedNotificationEventLimit: Int? {
        retentionInteger(
            from: notificationEventLimitText
        )
    }

    private var parsedActionRunLimit: Int? {
        retentionInteger(
            from: actionRunLimitText
        )
    }

    private func adjustNotificationEventLimit(
        by amount: Int
    ) {
        let range =
            AppPreferences.notificationEventRetentionRange

        let currentValue =
            parsedNotificationEventLimit
            ?? appliedRetentionConfiguration
                .notificationEventLimit

        let newValue = min(
            max(
                currentValue + amount,
                range.lowerBound
            ),
            range.upperBound
        )

        notificationEventLimitText =
            newValue.formatted()
    }

    private func adjustActionRunLimit(
        by amount: Int
    ) {
        let range =
            AppPreferences.actionRunRetentionRange

        let currentValue =
            parsedActionRunLimit
            ?? appliedRetentionConfiguration
                .actionRunLimit

        let newValue = min(
            max(
                currentValue + amount,
                range.lowerBound
            ),
            range.upperBound
        )

        actionRunLimitText =
            newValue.formatted()
    }

    private func resetRetentionLimitsToDefaults() {
        let defaults = RetentionConfiguration.defaults

        notificationEventLimitText =
            defaults.notificationEventLimit.formatted()

        actionRunLimitText =
            defaults.actionRunLimit.formatted()

        retentionErrorMessage = nil
    }

    private var retentionLimitsAreDefaults: Bool {
        guard
            let notificationEventLimit =
                parsedNotificationEventLimit,
            let actionRunLimit =
                parsedActionRunLimit
        else {
            return false
        }

        let defaults = RetentionConfiguration.defaults

        return notificationEventLimit
                == defaults.notificationEventLimit
            && actionRunLimit
                == defaults.actionRunLimit
    }

    private var canApplyRetentionLimits: Bool {
        guard !isApplyingRetentionLimits,
              let notificationEventLimit =
                  parsedNotificationEventLimit,
              let actionRunLimit =
                  parsedActionRunLimit,
              AppPreferences
                  .notificationEventRetentionRange
                  .contains(notificationEventLimit),
              AppPreferences
                  .actionRunRetentionRange
                  .contains(actionRunLimit)
        else {
            return false
        }

        return notificationEventLimit
                != appliedRetentionConfiguration
                    .notificationEventLimit
            || actionRunLimit
                != appliedRetentionConfiguration
                    .actionRunLimit
    }

    private func retentionInteger(
        from text: String
    ) -> Int? {
        let normalized =
            text
                .replacingOccurrences(
                    of: ",",
                    with: ""
                )
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

        return Int(normalized)
    }

    var body: some View {
        Form {
            Section {
                if let statistics {
                    LabeledContent(
                        "Activity events stored in database"
                    ) {
                        Text(
                            "\(statistics.notificationEventCount.formatted()) "
                                + "of "
                                + statistics.notificationEventLimit.formatted()
                        )
                    }

                    LabeledContent(
                        "Action runs stored in database"
                    ) {
                        Text(
                            "\(statistics.actionRunCount.formatted()) "
                                + "of "
                                + statistics.actionRunLimit.formatted()
                        )
                    }

                    LabeledContent(
                        "Database history range",
                        value:
                            historyRangeText(
                                for: statistics
                            )
                    )

                    LabeledContent(
                        "Database storage",
                        value:
                            databaseStorageText(
                                statistics
                                    .databaseStorageByteCount
                            )
                    )

                    LabeledContent(
                        "Database location"
                    ) {
                        Text(displayedDatabaseFilePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(databaseFileURL.path)
                    }
                    
                    LabeledContent(
                        "Monitoring sessions",
                        value:
                            statistics.watchSessionCount
                                .formatted()
                    )

                    LabeledContent(
                        "Configuration file"
                    ) {
                        Text(displayedConfigFilePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(configFileURL.path)
                    }
                } else if let errorMessage {
                    Label(
                        "Could not load database statistics",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                    .help(errorMessage)
                } else if hasLoadedStatistics {
                    Text(
                        "No Activity database is currently open."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Text("Loading database statistics…")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()

                    Button(
                        "Reset Activity Database…",
                        role: .destructive
                    ) {
                        isShowingResetConfirmation = true
                    }
                    .disabled(isResettingDatabase)
                }

                if let resetErrorMessage {
                    Label(
                        "Database reset failed",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                    .help(resetErrorMessage)
                }
            }

            Section {
                LabeledContent(
                    "Retain Activity events"
                ) {
                    HStack(spacing: 6) {
                        TextField(
                            "Activity event retention limit",
                            text:
                                $notificationEventLimitText
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        Stepper(
                            "Activity event retention limit",
                            onIncrement: {
                                adjustNotificationEventLimit(
                                    by: 1_000
                                )
                            },
                            onDecrement: {
                                adjustNotificationEventLimit(
                                    by: -1_000
                                )
                            }
                        )
                        .labelsHidden()
                    }
                }
                LabeledContent(
                    "Retain Action runs"
                ) {
                    HStack(spacing: 6) {
                        TextField(
                            "Action-run retention limit",
                            text:
                                $actionRunLimitText
                        )
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        Stepper(
                            "Action-run retention limit",
                            onIncrement: {
                                adjustActionRunLimit(
                                    by: 1_000
                                )
                            },
                            onDecrement: {
                                adjustActionRunLimit(
                                    by: -1_000
                                )
                            }
                        )
                        .labelsHidden()
                    }
                }
                Text(
                    "Lowering a limit immediately deletes the "
                        + "oldest excess history. Increasing a "
                        + "limit affects future retention."
                )
                .foregroundStyle(.secondary)
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )

                HStack {
                    Spacer()

                    Button(
                        "Reset to Default"
                    ) {
                        resetRetentionLimitsToDefaults()
                    }
                    .disabled(
                        isApplyingRetentionLimits
                            || retentionLimitsAreDefaults
                    )

                    Button(
                        "Apply Retention Limits"
                    ) {
                        applyRetentionLimits()
                    }
                    .disabled(
                        !canApplyRetentionLimits
                    )
                }
                if let retentionErrorMessage {
                    Label(
                        "Could not update retention limits",
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                    .help(retentionErrorMessage)
                }
            }

        }
        .formStyle(.grouped)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .alert(
            "Reset Activity Database?",
            isPresented:
                $isShowingResetConfirmation
        ) {
            Button("Cancel", role: .cancel) {}

            Button(
                "Reset Database",
                role: .destructive
            ) {
                performDatabaseReset()
            }
        } message: {
            Text(
                "This permanently removes all Activity history "
                    + "and creates a new database. Rules and "
                    + "settings are not affected. This action "
                    + "cannot be undone."
            )
        }
        .task {
            while !Task.isCancelled {
                refreshDatabaseStatistics()

                try? await Task.sleep(
                    for: .seconds(1)
                )
            }
        }
    }

    @MainActor
    private func applyRetentionLimits() {
        guard !isApplyingRetentionLimits,
              let notificationEventLimit =
                  parsedNotificationEventLimit,
              let actionRunLimit =
                  parsedActionRunLimit
        else {
            return
        }

        isApplyingRetentionLimits = true
        retentionErrorMessage = nil

        updateRetentionLimits(
            notificationEventLimit,
            actionRunLimit
        ) { result in
            isApplyingRetentionLimits = false

            switch result {
            case .updated:
                appliedRetentionConfiguration =
                    try! RetentionConfiguration(
                        notificationEventLimit:
                            notificationEventLimit,
                        actionRunLimit:
                            actionRunLimit
                    )
                notificationEventLimitText =
                    notificationEventLimit
                        .formatted()

                actionRunLimitText =
                    actionRunLimit
                        .formatted()

                refreshDatabaseStatistics()

            case let .failed(message):
                retentionErrorMessage = message
            }
        }
    }

    @MainActor
    private func performDatabaseReset() {
        guard !isResettingDatabase else {
            return
        }

        isResettingDatabase = true
        resetErrorMessage = nil

        resetActivityDatabase { result in
            isResettingDatabase = false

            switch result {
            case .reset:
                statistics = nil
                errorMessage = nil
                hasLoadedStatistics = false

                refreshDatabaseStatistics()

            case let .failed(message):
                resetErrorMessage = message
            }
        }
    }

    @MainActor
    private func refreshDatabaseStatistics() {
        guard !isLoading else {
            return
        }

        isLoading = true

        requestDatabaseStatistics { result in
            switch result {
            case let .loaded(statistics):
                self.statistics = statistics
                errorMessage = nil

            case let .failed(message):
                statistics = nil
                errorMessage = message
            }

            hasLoadedStatistics = true
            isLoading = false
        }
    }
}

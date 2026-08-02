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

    @State private var statistics:
        NotificationStoreStatistics?

    @State private var errorMessage: String?
    @State private var hasLoadedStatistics = false
    @State private var isLoading = false

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
    
    var body: some View {
        Form {
            Section("Database") {
                if let statistics {
                    LabeledContent(
                        "Activity events"
                    ) {
                        Text(
                            "\(statistics.notificationEventCount.formatted()) "
                                + "of "
                                + statistics.notificationEventLimit.formatted()
                        )
                    }

                    LabeledContent(
                        "Action runs"
                    ) {
                        Text(
                            "\(statistics.actionRunCount.formatted()) "
                                + "of "
                                + statistics.actionRunLimit.formatted()
                        )
                    }

                    LabeledContent(
                        "History range",
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
            }
        }
        .formStyle(.grouped)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
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

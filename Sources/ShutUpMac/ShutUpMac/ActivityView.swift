import SwiftUI

struct ActivityView: View {
    @ObservedObject var store: ActivityStore

    @State private var selectedRecordID:
        NotificationActivityRecord.ID?

    @State private var sortOrder:
        [KeyPathComparator<NotificationActivityRecord>] = [
            KeyPathComparator(
                \NotificationActivityRecord.appearedAt,
                order: .reverse
            )
        ]

    private var sortedRecords: [NotificationActivityRecord] {
        store.records.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if store.records.isEmpty {
                ContentUnavailableView(
                    "No Notifications Yet",
                    systemImage: "bell.badge",
                    description: Text(
                        "Notifications observed while ShutUpMac "
                        + "is running will appear here."
                    )
                )
            } else {
                Table(
                    sortedRecords,
                    selection: $selectedRecordID,
                    sortOrder: $sortOrder
                ) {
                    TableColumn(
                        "App",
                        value: \NotificationActivityRecord.app
                    ) { record in
                        Text(displayValue(record.app))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(displayValue(record.app))
                    }
                    .width(
                        min: 90,
                        ideal: 130,
                        max: 220
                    )

                    TableColumn(
                        "Title",
                        value: \NotificationActivityRecord.title
                    ) { record in
                        Text(displayValue(record.title))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(displayValue(record.title))
                    }
                    .width(
                        min: 120,
                        ideal: 190,
                        max: 400
                    )

                    TableColumn(
                        "Subtitle",
                        value: \NotificationActivityRecord.subtitle
                    ) { record in
                        Text(displayValue(record.subtitle))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(displayValue(record.subtitle))
                    }
                    .width(
                        min: 120,
                        ideal: 190,
                        max: 400
                    )

                    TableColumn(
                        "Body",
                        value: \NotificationActivityRecord.body
                    ) { record in
                        Text(displayValue(record.body))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(displayValue(record.body))
                    }
                    .width(
                        min: 180,
                        ideal: 320,
                        max: 700
                    )

                    TableColumn(
                        "Rules matched",
                        value:
                            \NotificationActivityRecord.rulesMatchedDisplay
                    ) { record in
                        Text(record.rulesMatchedDisplay)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(record.rulesMatchedDisplay)
                    }
                    .width(
                        min: 120,
                        ideal: 180,
                        max: 350
                    )

                    TableColumn(
                        "Appeared",
                        value:
                            \NotificationActivityRecord.appearedAt
                    ) { record in
                        Text(
                            record.appearedAt,
                            format: .dateTime
                                .month(.abbreviated)
                                .day()
                                .hour()
                                .minute()
                                .second()
                        )
                        .lineLimit(1)
                    }
                    .width(
                        min: 145,
                        ideal: 165,
                        max: 210
                    )
                }
            }
        }
        .frame(
            minWidth: 960,
            minHeight: 420
        )
        .toolbar {
            ToolbarItem {
                Button("Clear") {
                    selectedRecordID = nil
                    store.removeAll()
                }
                .disabled(store.records.isEmpty)
            }
        }
    }

    private func displayValue(
        _ value: String
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? "—" : trimmed
    }

}

private struct ActivityDetailView: View {
    let item: ActivityItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailSection("Activity") {
                    detailRow("Type", kindLabel)
                    detailRow(
                        "Timestamp",
                        item.timestamp.formatted(
                            date: .abbreviated,
                            time: .standard
                        )
                    )
                    detailRow("Summary", item.summary)

                    if let detail = nonempty(item.detail) {
                        detailRow("Detail", detail)
                    }
                }

                if let notification = item.notification {
                    detailSection("Notification") {
                        detailRow("Application", notification.app)
                        detailRow("Title", notification.title)
                        detailRow("Subtitle", notification.subtitle)
                        detailRow("Body", notification.body)
                        detailRow("Key", notification.key)
                    }
                }

                if item.ruleName != nil
                    || item.actionRunID != nil
                    || item.status != nil {
                    detailSection("Action") {
                        if let ruleName = nonempty(item.ruleName) {
                            detailRow("Rule", ruleName)
                        }

                        if let actionRunID = item.actionRunID {
                            detailRow(
                                "Action run ID",
                                String(actionRunID)
                            )
                        }

                        if let status = nonempty(item.status) {
                            detailRow("Status", status)
                        }
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .topLeading
            )
            .padding()
        }
    }

    @ViewBuilder
    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content()
        }
    }

    @ViewBuilder
    private func detailRow(
        _ label: String,
        _ value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
        }
    }

    private func nonempty(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmed.isEmpty ? nil : trimmed
    }

    private var kindLabel: String {
        switch item.kind {
        case .notificationAppeared:
            return "Notification appeared"

        case .notificationDisappeared:
            return "Notification disappeared"

        case .notificationDisappearedUnobserved:
            return "Recovered disappearance"

        case .actionRun:
            return "Action executed"

        case .actionVerification:
            return "Action verification"
        }
    }
}

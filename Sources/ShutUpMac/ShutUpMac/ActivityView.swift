import SwiftUI

struct ActivityView: View {
    @ObservedObject var store: ActivityStore
    
    @State private var searchText = ""
    
    @State private var selectedRecordID:
    NotificationActivityRecord.ID?
    
    @State private var sortOrder:
    [KeyPathComparator<NotificationActivityRecord>] = [
        KeyPathComparator(
            \NotificationActivityRecord.appearedAt,
             order: .reverse
        )
    ]
    
    private var displayedRecords: [NotificationActivityRecord] {
        let filteredRecords: [NotificationActivityRecord]
        
        if trimmedSearchText.isEmpty {
            filteredRecords = store.records
        } else {
            filteredRecords = store.records.filter { record in
                record.matchesSearch(trimmedSearchText)
            }
        }
        
        return filteredRecords.sorted(using: sortOrder)
    }
    
    private var trimmedSearchText: String {
        searchText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
    
    private var oldestRetainedDate: Date? {
        store.records.map(\.appearedAt).min()
    }
    
    private var activityStatusText: String? {
        guard let oldestRetainedDate else {
            return nil
        }
        
        let count = displayedRecords.count
        let notificationWord =
        count == 1 ? "notification" : "notifications"
        
        let prefix: String
        
        if trimmedSearchText.isEmpty {
            prefix = "\(count) \(notificationWord)"
        } else {
            prefix = "\(count) matching \(notificationWord)"
        }
        
        return prefix
        + " since "
        + oldestRetainedDate.formatted(
            date: .abbreviated,
            time: .omitted
        )
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
                VStack(spacing: 0) {
                    ZStack {
                        Table(
                            displayedRecords,
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
                            
                            TableColumn("Notification") { record in
                                VStack(
                                    alignment: .leading,
                                    spacing: 2
                                ) {
                                    if let displayTitle = record.displayTitle {
                                        Text(previewValue(displayTitle))
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                    }
                                    
                                    if let displaySubtitle = record.displaySubtitle {
                                        Text(previewValue(displaySubtitle))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    if !record.body.isEmpty {
                                        Text(previewValue(record.body))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .help(
                                    [record.title, record.subtitle, record.body]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: "\n")
                                )
                            }
                            .width(
                                min: 240,
                                ideal: 250
                            )
                            
                            TableColumn(
                                "Rules matched",
                                value:
                                    \NotificationActivityRecord.matchedRuleCount
                            ) { record in
                                RulesMatchedCell(
                                    matchedRules: record.matchedRules,
                                    displayText: record.rulesMatchedDisplay
                                )
                            }
                            .width(
                                min: 120,
                                ideal: 160,
                                max: 220
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

                        if store.records.isEmpty {
                            Text("No notification activity")
                                .foregroundStyle(.secondary)
                        } else if !trimmedSearchText.isEmpty
                            && displayedRecords.isEmpty {
                            Text("No matching notifications")
                                .foregroundStyle(.secondary)
                        }
                    }    
                
                    Divider()

                    HStack {
                        if let activityStatusText {
                            Text(activityStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }    
                .searchable(
                    text: $searchText,
                    placement: .toolbar,
                    prompt: "Search notifications"
                )
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
    
    private func previewValue(
        _ value: String,
        maximumLength: Int = 40
    ) -> String {
        let trimmed = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        
        guard trimmed.count > maximumLength else {
            return trimmed
        }
        
        return String(
            trimmed.prefix(maximumLength - 1)
        ) + "…"
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

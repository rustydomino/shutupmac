import SwiftUI

struct ActivityView: View {
    @ObservedObject var store: ActivityStore

    var body: some View {
        Group {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "No Activity Yet",
                    systemImage: "bell.badge",
                    description: Text(
                        "Notification activity observed while "
                        + "ShutUpMac is running will appear here."
                    )
                )
            } else {
                List(store.items) { item in
                    ActivityItemRow(item: item)
                }
            }
        }
        .frame(
            minWidth: 720,
            minHeight: 420
        )
        .toolbar {
            ToolbarItem {
                Button("Clear") {
                    store.removeAll()
                }
                .disabled(store.items.isEmpty)
            }
        }
    }
}

private struct ActivityItemRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .frame(width: 20)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.summary)
                        .fontWeight(.medium)

                    Spacer()

                    Text(
                        item.timestamp,
                        format: .dateTime
                            .hour()
                            .minute()
                            .second()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text(kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let detail = item.detail,
                   !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let status = item.status,
                   !status.isEmpty {
                    Text("Status: \(status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch item.kind {
        case .notificationAppeared:
            return "bell.badge"

        case .notificationDisappeared:
            return "bell.slash"

        case .notificationDisappearedUnobserved:
            return "clock.arrow.circlepath"

        case .actionRun:
            return "bolt"

        case .actionVerification:
            return "checkmark.seal"
        }
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

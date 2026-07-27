import Combine
import Foundation

/// Main-actor storage observed by the Activity viewer.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var items: [ActivityItem] = []
    @Published private(set) var records: [NotificationActivityRecord] = []

    private let maximumItemCount: Int

    init(maximumItemCount: Int = 1_000) {
        self.maximumItemCount = maximumItemCount
    }

    func append(_ newItems: [ActivityItem]) {
        guard !newItems.isEmpty else {
            return
        }

        items.append(contentsOf: newItems)
        
        for item in newItems {
            appendToRecord(item)
        }

        items.sort {
            $0.timestamp > $1.timestamp
        }

        records.sort {
            $0.appearedAt > $1.appearedAt
        }
        
        if items.count > maximumItemCount {
            items.removeLast(
                items.count - maximumItemCount
            )
        }
        
        if records.count > maximumItemCount {
            records.removeLast(
                records.count - maximumItemCount
            )
        }
        
    }

    func loadHistoricalRecords(
        _ historicalRecords: [NotificationActivityRecord]
    ) {
        records = Array(
            historicalRecords
                .sorted {
                    $0.appearedAt < $1.appearedAt
                }
                .suffix(maximumItemCount)
        )

        items = []
    }

    func removeAll() {
        items.removeAll()
        records.removeAll()
    }
    
    private func appendToRecord(
        _ item: ActivityItem
    ) {
        guard let notification = item.notification else {
            return
        }

        if let index = records.firstIndex(
            where: { $0.id == notification.key }
        ) {
            records[index].append(item)
            return
        }

        guard let newRecord =
            NotificationActivityRecord(from: item) else {
            return
        }

        records.append(newRecord)
    }
    
}

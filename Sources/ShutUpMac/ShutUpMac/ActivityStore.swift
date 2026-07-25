import Combine
import Foundation

/// Main-actor storage observed by the Activity viewer.
@MainActor
final class ActivityStore: ObservableObject {
    @Published private(set) var items: [ActivityItem] = []

    private let maximumItemCount: Int

    init(maximumItemCount: Int = 1_000) {
        self.maximumItemCount = maximumItemCount
    }

    func append(_ newItems: [ActivityItem]) {
        guard !newItems.isEmpty else {
            return
        }

        items.append(contentsOf: newItems)

        items.sort {
            $0.timestamp > $1.timestamp
        }

        if items.count > maximumItemCount {
            items.removeLast(
                items.count - maximumItemCount
            )
        }
    }

    func removeAll() {
        items.removeAll()
    }
}

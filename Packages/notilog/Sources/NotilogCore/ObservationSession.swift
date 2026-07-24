import Foundation

public struct ObservationSession {
    public let id: String
    public let startedAt: Date

    public init(id: String = UUID().uuidString, startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
    }
}

import Foundation

public enum NotificationExceptionField:
    String,
    Codable,
    Sendable {
    case title
    case subtitle
    case body
}

public struct NotificationException:
    Equatable,
    Sendable {
    public let field: NotificationExceptionField
    public let searchText: String

    public init(
        field: NotificationExceptionField,
        searchText: String
    ) {
        self.field = field
        self.searchText = searchText
    }

    public func matches(
        _ notification: VisibleNotification,
        caseSensitive: Bool
    ) -> Bool {
        let fieldValue: String

        switch field {
        case .title:
            fieldValue = notification.title

        case .subtitle:
            fieldValue = notification.subtitle

        case .body:
            fieldValue = notification.body
        }

        if caseSensitive {
            return fieldValue.contains(searchText)
        }

        return fieldValue
            .lowercased()
            .contains(searchText.lowercased())
    }
}
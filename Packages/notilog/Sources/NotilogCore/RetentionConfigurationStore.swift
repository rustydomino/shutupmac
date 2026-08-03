import Foundation

public enum RetentionConfigurationLoadResult:
    Equatable,
    Sendable
{
    case missing(
        defaults: RetentionConfiguration
    )

    case loaded(
        RetentionConfiguration
    )

    public var configuration:
        RetentionConfiguration
    {
        switch self {
        case let .missing(defaults):
            return defaults

        case let .loaded(configuration):
            return configuration
        }
    }
}

public struct RetentionConfigurationStore:
    Sendable
{
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws
        -> RetentionConfigurationLoadResult
    {
        guard FileManager.default.fileExists(
            atPath: fileURL.path
        ) else {
            return .missing(
                defaults:
                    RetentionConfiguration.defaults
            )
        }

        let data: Data

        do {
            data = try Data(
                contentsOf: fileURL
            )
        } catch {
            throw NotilogError
                .retentionConfigurationReadFailed(
                    path: fileURL.path,
                    message: error.localizedDescription
                )
        }

        do {
            let configuration =
                try JSONDecoder().decode(
                    RetentionConfiguration.self,
                    from: data
                )

            return .loaded(configuration)
        } catch {
            if let validationError =
                Self.validationError(
                    from: error
                )
            {
                throw validationError
            }

            throw NotilogError
                .retentionConfigurationReadFailed(
                    path: fileURL.path,
                    message: error.localizedDescription
                )
        }
    }

    public func save(
        _ configuration:
            RetentionConfiguration
    ) throws {
        let parentURL =
            fileURL.deletingLastPathComponent()

        do {
            try FileManager.default
                .createDirectory(
                    at: parentURL,
                    withIntermediateDirectories: true
                )
        } catch {
            throw NotilogError
                .retentionConfigurationWriteFailed(
                    path: fileURL.path,
                    message: error.localizedDescription
                )
        }

        let encoder = JSONEncoder()

        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]

        let encodedData: Data

        do {
            encodedData = try encoder.encode(
                configuration
            )
        } catch {
            throw NotilogError
                .retentionConfigurationWriteFailed(
                    path: fileURL.path,
                    message: error.localizedDescription
                )
        }

        var fileData = encodedData
        fileData.append(0x0A)

        do {
            try fileData.write(
                to: fileURL,
                options: .atomic
            )
        } catch {
            throw NotilogError
                .retentionConfigurationWriteFailed(
                    path: fileURL.path,
                    message: error.localizedDescription
                )
        }
    }

    private static func validationError(
        from error: Error
    ) -> NotilogError? {
        guard
            case let DecodingError
                .dataCorrupted(context) = error
        else {
            return nil
        }

        return context.underlyingError
            as? NotilogError
    }
}
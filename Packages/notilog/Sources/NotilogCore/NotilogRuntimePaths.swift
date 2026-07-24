import Foundation

/// Describes the filesystem locations used by a Notilog runtime.
///
/// Hosts such as `notilog-cli` and ShutUpMac can construct different path
/// configurations without requiring NotilogCore to assume one global
/// Application Support directory.
public struct NotilogRuntimePaths: Equatable, Sendable {
    public let applicationSupport: URL
    public let database: URL
    public let config: URL
    public let logs: URL

    /// Creates the conventional Notilog directory layout beneath a supplied
    /// Application Support directory.
    public init(applicationSupport: URL) {
        self.applicationSupport = applicationSupport
        self.database = applicationSupport
            .appendingPathComponent("notilog.sqlite")
        self.config = applicationSupport
            .appendingPathComponent("config.json")
        self.logs = applicationSupport
            .appendingPathComponent("logs", isDirectory: true)
    }

    /// Creates a runtime path configuration with explicitly supplied URLs.
    public init(
        applicationSupport: URL,
        database: URL,
        config: URL,
        logs: URL
    ) {
        self.applicationSupport = applicationSupport
        self.database = database
        self.config = config
        self.logs = logs
    }

    /// Returns the existing standalone Notilog filesystem layout:
    ///
    ///     ~/Library/Application Support/notilog/
    ///
    /// The CLI will continue using this factory during the refactor so that
    /// existing configuration and database files remain in place.
    public static func legacyNotilogDefault(
        fileManager: FileManager = .default
    ) -> Self {
        let base = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return Self(
            applicationSupport: base.appendingPathComponent(
                "notilog",
                isDirectory: true
            )
        )
    }

    /// Creates the directories required before the runtime opens its files.
    public func ensureDirectoriesExist(
        fileManager: FileManager = .default
    ) throws {
        try fileManager.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )

        try fileManager.createDirectory(
            at: logs,
            withIntermediateDirectories: true
        )
    }
}
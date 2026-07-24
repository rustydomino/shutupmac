import Foundation

public enum Paths {
    public static let applicationSupport: URL = {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!

        return base.appendingPathComponent("notilog", isDirectory: true)
    }()

    public static let database: URL =
        applicationSupport.appendingPathComponent("notilog.sqlite")

    public static let config: URL =
        applicationSupport.appendingPathComponent("config.json")

    public static let logs: URL =
        applicationSupport.appendingPathComponent("logs", isDirectory: true)

    public static func ensureRuntimeDirectoriesExist() throws {
        try FileManager.default.createDirectory(
            at: applicationSupport,
            withIntermediateDirectories: true
        )

        try FileManager.default.createDirectory(
            at: logs,
            withIntermediateDirectories: true
        )
    }
}

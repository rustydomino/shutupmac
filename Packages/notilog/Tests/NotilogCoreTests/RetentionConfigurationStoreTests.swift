import Foundation
@testable import NotilogCore
import XCTest

final class RetentionConfigurationStoreTests:
    XCTestCase
{
    func testMissingFileUsesDefaultsWithoutCreatingAnything()
        throws
    {
        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-retention-\(UUID().uuidString)",
                    isDirectory: true
                )

        let fileURL =
            directoryURL.appendingPathComponent(
                "retention.json"
            )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let store =
            RetentionConfigurationStore(
                fileURL: fileURL
            )

        let result = try store.load()

        XCTAssertEqual(
            result,
            .missing(
                defaults:
                    RetentionConfiguration.defaults
            )
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: directoryURL.path
            )
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fileURL.path
            )
        )
    }

    func testSaveAndLoadConfiguration() throws {
        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-retention-\(UUID().uuidString)",
                    isDirectory: true
                )

        let fileURL =
            directoryURL.appendingPathComponent(
                "retention.json"
            )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let store =
            RetentionConfigurationStore(
                fileURL: fileURL
            )

        let configuration =
            try RetentionConfiguration(
                notificationEventLimit: 12_345,
                actionRunLimit: 6_789
            )

        try store.save(configuration)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fileURL.path
            )
        )

        XCTAssertEqual(
            try store.load(),
            .loaded(configuration)
        )
    }

    func testOutOfRangeConfigurationIsRejectedAndPreserved()
        throws
    {
        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-retention-\(UUID().uuidString)",
                    isDirectory: true
                )

        let fileURL =
            directoryURL.appendingPathComponent(
                "retention.json"
            )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let originalData = Data(
            """
            {
            "notificationEventLimit": 999,
            "actionRunLimit": 10000
            }
            """.utf8
        )

        try originalData.write(to: fileURL)

        let store =
            RetentionConfigurationStore(
                fileURL: fileURL
            )

        XCTAssertThrowsError(
            try store.load()
        ) { error in
            guard case NotilogError
                .invalidRetentionConfiguration = error
            else {
                XCTFail(
                    "Expected invalidRetentionConfiguration, " +
                        "got \(error)"
                )
                return
            }
        }

        XCTAssertEqual(
            try Data(contentsOf: fileURL),
            originalData
        )
    }

    func testMalformedConfigurationIsRejectedAndPreserved()
        throws
    {
        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-retention-\(UUID().uuidString)",
                    isDirectory: true
                )

        let fileURL =
            directoryURL.appendingPathComponent(
                "retention.json"
            )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let originalData = Data(
            """
            {
            "notificationEventLimit": 25000,
            "actionRunLimit":
            }
            """.utf8
        )

        try originalData.write(to: fileURL)

        let store =
            RetentionConfigurationStore(
                fileURL: fileURL
            )

        XCTAssertThrowsError(
            try store.load()
        ) { error in
            guard case NotilogError
                .retentionConfigurationReadFailed(
                    path: fileURL.path,
                    message: _
                ) = error
            else {
                XCTFail(
                    "Expected retentionConfigurationReadFailed, " +
                        "got \(error)"
                )
                return
            }
        }

        XCTAssertEqual(
            try Data(contentsOf: fileURL),
            originalData
        )
    }

    func testSaveAtomicallyReplacesExistingConfiguration()
        throws
    {
        let directoryURL =
            FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "notilog-retention-\(UUID().uuidString)",
                    isDirectory: true
                )

        let fileURL =
            directoryURL.appendingPathComponent(
                "retention.json"
            )

        defer {
            try? FileManager.default.removeItem(
                at: directoryURL
            )
        }

        let store =
            RetentionConfigurationStore(
                fileURL: fileURL
            )

        let original =
            try RetentionConfiguration(
                notificationEventLimit: 20_000,
                actionRunLimit: 8_000
            )

        let replacement =
            try RetentionConfiguration(
                notificationEventLimit: 40_000,
                actionRunLimit: 15_000
            )

        try store.save(original)
        try store.save(replacement)

        XCTAssertEqual(
            try store.load(),
            .loaded(replacement)
        )

        let fileContents =
            try String(
                contentsOf: fileURL,
                encoding: .utf8
            )

        XCTAssertFalse(
            fileContents.contains("20000")
        )

        XCTAssertFalse(
            fileContents.contains("8000")
        )

        XCTAssertTrue(
            fileContents.hasSuffix("\n")
        )
    }

}

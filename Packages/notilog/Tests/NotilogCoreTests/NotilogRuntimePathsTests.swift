import Foundation
@testable import NotilogCore
import XCTest

final class NotilogRuntimePathsTests: XCTestCase {
    func testDerivesStandardPathsFromApplicationSupportDirectory() {
        let applicationSupport = URL(
            fileURLWithPath: "/tmp/notilog-runtime-test",
            isDirectory: true
        )

        let paths = NotilogRuntimePaths(
            applicationSupport: applicationSupport
        )

        XCTAssertEqual(
            paths.applicationSupport,
            applicationSupport
        )

        XCTAssertEqual(
            paths.database,
            applicationSupport.appendingPathComponent("notilog.sqlite")
        )

        XCTAssertEqual(
            paths.config,
            applicationSupport.appendingPathComponent("config.json")
        )

        XCTAssertEqual(
            paths.logs,
            applicationSupport.appendingPathComponent(
                "logs",
                isDirectory: true
            )
        )
    }

    func testEnsureDirectoriesExistCreatesRuntimeDirectories() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "notilog-runtime-\(UUID().uuidString)",
                isDirectory: true
            )

        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let applicationSupport = temporaryRoot
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("notilog", isDirectory: true)

        let paths = NotilogRuntimePaths(
            applicationSupport: applicationSupport
        )

        try paths.ensureDirectoriesExist()

        var isDirectory: ObjCBool = false

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.applicationSupport.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)

        isDirectory = false

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: paths.logs.path,
                isDirectory: &isDirectory
            )
        )
        XCTAssertTrue(isDirectory.boolValue)

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.database.path
            )
        )

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.config.path
            )
        )
    }
}
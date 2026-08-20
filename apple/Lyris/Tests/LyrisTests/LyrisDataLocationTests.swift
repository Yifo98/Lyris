import Foundation
import XCTest
@testable import Lyris

final class LyrisDataLocationTests: XCTestCase {
    func testLegacyApplicationSupportDirectoryMovesToLyrisWithoutLosingFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisDataLocationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let legacy = root.appendingPathComponent("MeloFloat", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let marker = legacy.appendingPathComponent("settings.json")
        try Data("preserved".utf8).write(to: marker)

        let result = LyrisDataLocation.migrateLegacyApplicationSupportIfNeeded(
            applicationSupportURL: root
        )

        XCTAssertEqual(result.lastPathComponent, "Lyris")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(
            try String(contentsOf: result.appendingPathComponent("settings.json")),
            "preserved"
        )
    }

    func testExistingLyrisDirectoryAlwaysWinsOverLegacyDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyrisDataLocationTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let current = root.appendingPathComponent("Lyris", isDirectory: true)
        let legacy = root.appendingPathComponent("MeloFloat", isDirectory: true)
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)

        let result = LyrisDataLocation.migrateLegacyApplicationSupportIfNeeded(
            applicationSupportURL: root
        )

        XCTAssertEqual(result, current)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }
}

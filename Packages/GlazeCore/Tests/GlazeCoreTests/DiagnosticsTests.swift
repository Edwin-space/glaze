import Foundation
import XCTest
@testable import GlazeCore

final class DiagnosticsTests: XCTestCase {
    func testOptInPersistenceExportAndDeletion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let center = DiagnosticsCenter(directory: directory, defaults: defaults)
        XCTAssertFalse(center.isEnabled)
        center.record("test.disabled")
        var report = try String(contentsOf: await center.export(), encoding: .utf8)
        XCTAssertFalse(report.contains("test.disabled"))
        center.setEnabled(true)
        let privateURL = "https://user:secret@private-nas/movie-name.mkv?token=secret"
        center.record("test.safe", id: center.token(for: privateURL), numbers: ["status": 207])
        center.record("test.invalid_id", id: privateURL)
        report = try String(contentsOf: await center.export(), encoding: .utf8)
        XCTAssertTrue(report.contains("test.safe"))
        for value in ["secret", "private-nas", "movie-name", "user:"] { XCTAssertFalse(report.contains(value)) }
        let restored = DiagnosticsCenter(directory: directory, defaults: defaults)
        XCTAssertTrue(restored.isEnabled)
        XCTAssertEqual(center.token(for: privateURL), restored.token(for: privateURL))
        await center.clear()
        report = try String(contentsOf: await center.export(), encoding: .utf8)
        XCTAssertFalse(report.contains("test.safe"))
    }

    func testRotationAndDisabledModeDoNotGrowLogs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let center = DiagnosticsCenter(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!, maximumBytes: 500)
        center.setEnabled(true)
        for _ in 0..<100 { center.record("test.rotate", numbers: ["value": 1]) }
        _ = try await center.export() // Drains all preceding writes.
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        XCTAssertLessThanOrEqual(files.count, 3)
        for file in files { XCTAssertLessThanOrEqual(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!, 500) }
        center.setEnabled(false)
        center.record("test.after_disable")
        let report = try String(contentsOf: await center.export(), encoding: .utf8)
        XCTAssertFalse(report.contains("test.after_disable"))
        await center.clear()
    }
}

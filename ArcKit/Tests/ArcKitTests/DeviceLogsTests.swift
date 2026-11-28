import Foundation
import XCTest
@testable import ArcKit

final class DeviceLogsTests: XCTestCase {
    func testDiskProjectionContainsOnlyKnownEventsAndWireFields() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("logs.json")
        let seed = #"{"entries":[{"time_ms":1,"level":"warn","event":"request_failed","raw":"https://private.test/?token=secret-pin-password"}]}"#
        try Data(seed.utf8).write(to: file)
        let journal = DeviceLogs(file: file)
        journal.record(.debug, .playbackStarted)
        XCTAssertEqual(journal.snapshot().map(\.event), [.requestFailed])
        let projected = try JSONEncoder().encode(journal.snapshot())
        XCTAssertFalse(String(decoding: projected, as: UTF8.self).contains("secret"))
        journal.setDetailed(true)
        journal.record(.debug, .playbackStarted)
        XCTAssertEqual(journal.snapshot().map(\.event), [.requestFailed, .detailedEnabled, .playbackStarted])
        journal.clear()
        XCTAssertTrue(DeviceLogs(file: file).snapshot().isEmpty)
    }
}

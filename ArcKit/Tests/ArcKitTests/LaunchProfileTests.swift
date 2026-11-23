import Foundation
import XCTest
@testable import ArcKit

final class LaunchProfileTests: XCTestCase {
    private func status(pin: Bool = false) throws -> AuthStatus {
        try ArcJSON.decoder.decode(AuthStatus.self, from: Data("""
        {"signed_in":true,"profile":{"id":"a","name":"Jordan"},"profiles":[
          {"id":"a","name":"Jordan"},{"id":"b","name":"Alex","has_pin":\(pin)}
        ]}
        """.utf8))
    }

    func testFreshLaunchUsesPickerAndResumeKeepsProfile() throws {
        let status = try status()
        XCTAssertNil(LaunchProfile.directProfile(status: status, automaticId: nil, fresh: true))
        XCTAssertEqual(LaunchProfile.directProfile(status: status, automaticId: "b", fresh: false)?.id, "a")
    }

    func testAutomaticProfileCanDifferFromLastProfile() throws {
        XCTAssertEqual(LaunchProfile.directProfile(status: try status(), automaticId: "b", fresh: true)?.id, "b")
    }

    func testLockedAndDeletedProfilesOpenPicker() throws {
        XCTAssertNil(LaunchProfile.directProfile(status: try status(pin: true), automaticId: "b", fresh: true))
        XCTAssertNil(LaunchProfile.directProfile(status: try status(), automaticId: "deleted", fresh: true))
    }
}

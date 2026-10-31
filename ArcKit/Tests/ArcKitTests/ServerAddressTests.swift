import XCTest
@testable import ArcKit

final class ServerAddressTests: XCTestCase {
    private func norm(_ s: String) -> String? { ServerAddress.normalize(s).map(ServerAddress.display) }

    func testAddressesTypedWithARemote() {
        XCTAssertEqual(norm("192.168.1.20"), "http://192.168.1.20:8099")
        XCTAssertEqual(norm("  arc.example.com/  "), "http://arc.example.com:8099")
        XCTAssertEqual(norm("arc.local:9000"), "http://arc.local:9000")
        XCTAssertEqual(norm("HTTPS://arc.example.com/web?x=1#y"), "https://arc.example.com")
        XCTAssertEqual(norm("http://10.0.0.5:8099/"), "http://10.0.0.5:8099")
    }

    func testThingsThatArentAddresses() {
        XCTAssertNil(norm(""))
        XCTAssertNil(norm("arc example"))
        XCTAssertNil(norm("https://"))
        XCTAssertNil(norm("ftp://arc.example.com"))
    }
}

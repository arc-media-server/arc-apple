import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A network of stand-ins, answering by host (the scan asks many at once, in no set order).
final class StubNetwork: URLProtocol {
    nonisolated(unsafe) static var hosts: [String: (Int, String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host, let (status, body) = Self.hosts[host] else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class DiscoveryTests: XCTestCase {
    func testCandidatesOnAHomeNetwork() {
        let hosts = Discovery.candidates(address: [192, 168, 1, 20], prefix: 24)
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts.first, "192.168.1.1")
        XCTAssertEqual(hosts.last, "192.168.1.254")
        XCTAssertFalse(hosts.contains("192.168.1.20"))
    }

    func testCandidatesStayWithinTheOwnSlash24() {
        let hosts = Discovery.candidates(address: [10, 0, 5, 9], prefix: 16)
        XCTAssertEqual(hosts.count, 253)
        XCTAssertTrue(hosts.allSatisfy { $0.hasPrefix("10.0.5.") })
        XCTAssertEqual(Discovery.candidates(address: [192, 168, 1, 2], prefix: 31), [])
        XCTAssertEqual(Discovery.candidates(address: [192, 168, 1, 2], prefix: 26).count, 61)
    }

    func testPrivateNetworksOnly() {
        XCTAssertTrue(Discovery.isPrivate([10, 1, 2, 3]))
        XCTAssertTrue(Discovery.isPrivate([172, 20, 0, 1]))
        XCTAssertTrue(Discovery.isPrivate([192, 168, 0, 1]))
        XCTAssertFalse(Discovery.isPrivate([172, 32, 0, 1]))
        XCTAssertFalse(Discovery.isPrivate([8, 8, 8, 8]))
    }

    func testScanFindsArcOnceAndIgnoresOthers() async {
        StubNetwork.hosts = [
            "192.168.1.5": (200, #"{"product":"arc","id":"srv1","name":"Living Room","version":"1.2","api_version":1}"#),
            "192.168.1.6": (200, #"{"product":"arc","id":"srv1","name":"Living Room","version":"1.2","api_version":1}"#),
            "192.168.1.7": (200, #"{"product":"other","id":"x","name":"Not Arc","api_version":1}"#),
            "192.168.1.8": (404, "{}"),
            "192.168.1.9": (200, #"{"product":"arc","id":"srv2","name":"attic","version":"1.3","api_version":1}"#),
        ]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubNetwork.self]
        let found = await Discovery.scan(hosts: (1...12).map { "192.168.1.\($0)" }, session: URLSession(configuration: config), parallel: 4)
        XCTAssertEqual(found.map(\.name), ["attic", "Living Room"])
        XCTAssertEqual(found.first?.address.absoluteString, "http://192.168.1.9:8099")
        XCTAssertEqual(found.first?.version, "1.3")
    }
}

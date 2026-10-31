import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A stand-in Arc: answers queued per test, requests recorded.
final class StubArc: URLProtocol {
    struct Answer { let status: Int; let body: String }
    nonisolated(unsafe) static var answers: [Answer] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.body(of: request))
        let answer = Self.answers.isEmpty ? Answer(status: 500, body: "{}") : Self.answers.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

final class ArcAPITests: XCTestCase {
    private var api: ArcAPI!

    override func setUp() {
        StubArc.answers = []
        StubArc.requests = []
        StubArc.bodies = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubArc.self]
        api = ArcAPI(baseURL: URL(string: "http://arc.test:8099")!, session: URLSession(configuration: config), token: { "t0k" })
    }

    private func answer(_ status: Int, _ body: String = "{}") { StubArc.answers.append(.init(status: status, body: body)) }

    func testSignInWithACode() async throws {
        answer(200, #"{"code":"ABCD","poll":"p/1","expires_in":600}"#)
        answer(202)
        answer(200, #"{"token":"new"}"#)
        answer(404)
        let link = try await api.startLink(device: "Living Room")
        XCTAssertEqual(link.code, "ABCD")
        let waiting = try await api.pollLink(link.poll)
        XCTAssertEqual(waiting, .waiting)
        let approved = try await api.pollLink(link.poll)
        XCTAssertEqual(approved, .approved(token: "new"))
        let expired = try await api.pollLink(link.poll)
        XCTAssertEqual(expired, .expired)
        XCTAssertEqual(StubArc.requests[0].url?.path, "/api/v1/auth/link")
        XCTAssertEqual(StubArc.bodies[0], #"{"device":"Living Room"}"#)
        XCTAssertEqual(StubArc.requests[1].url?.absoluteString, "http://arc.test:8099/api/v1/auth/link/p%2F1")
        XCTAssertEqual(StubArc.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
    }

    func testArcsRefusalsCarryItsMessageAndWhatItNeeds() async {
        answer(403, #"{"error":"Wrong PIN","needs":"pin"}"#)
        do {
            _ = try await api.chooseProfile(id: "u1", pin: "1234")
            XCTFail("expected a refusal")
        } catch let error as APIError {
            XCTAssertEqual(error.status, 403)
            XCTAssertEqual(error.message, "Wrong PIN")
            XCTAssertEqual(error.needs, "pin")
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(StubArc.bodies[0], #"{"id":"u1","pin":"1234"}"#)
    }

    func testBrowsingAndPlayingAddresses() async throws {
        answer(200, #"{"total":1,"items":[{"id":"m1","kind":"movie","title":"Heat"}]}"#)
        answer(200, #"{"method":"remux","url":"/api/transcode/s1/index.m3u8","hls":true,"session_id":"s1","offset_ms":12000}"#)
        let page = try await api.items(["library_id": "1", "sort": "added", "kind": "movie"])
        XCTAssertEqual(page.items.first?.title, "Heat")
        XCTAssertEqual(StubArc.requests[0].url?.query, "kind=movie&library_id=1&sort=added")
        let plan = try await api.startPlayback(itemId: "m1", request: PlaybackRequest(caps: PlayerCaps(containers: [], video: [], audio: [], maxHeight: 1080)))
        XCTAssertEqual(plan.offsetMs, 12_000)
        XCTAssertEqual(plan.audioStream, -1)
        XCTAssertEqual(api.absolute(plan.url)?.absoluteString, "http://arc.test:8099/api/v1/transcode/s1/index.m3u8")
        XCTAssertEqual(api.absolute("/api/v1/items/m1/image")?.absoluteString, "http://arc.test:8099/api/v1/items/m1/image")
    }

    func testAnAnswerItCantReadIsAFailureNotACrash() async {
        answer(200, #"{"name":5}"#)
        do {
            _ = try await api.identity()
            XCTFail("expected a failure")
        } catch {
            XCTAssertTrue(error is UnexpectedAnswer)
        }
    }
}

import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class LiveUpdatesTests: XCTestCase {
    override func setUp() {
        StubArc.answers = []
        StubArc.requests = []
        StubArc.bodies = []
    }

    func testLinesSplitOnEveryKindOfLineBreakAcrossChunks() {
        var splitter = SSELineSplitter()
        XCTAssertEqual(splitter.feed(Data("event: a\r".utf8)), ["event: a"])
        XCTAssertEqual(splitter.feed(Data("\ndata: x\n\nid: 3".utf8)), ["data: x", ""])
        XCTAssertEqual(splitter.feed(Data("\r\r".utf8)), ["id: 3", ""])
    }

    func testABareResyncEventStillCounts() {
        var parser = SSEParser()
        XCTAssertNil(parser.feed("event: resync"))
        XCTAssertEqual(parser.feed("")?.name, "resync")
        XCTAssertNil(parser.feed(": heartbeat"))
        XCTAssertNil(parser.feed(""))
    }

    func testTopicsTouchScreens() {
        XCTAssertEqual(LiveTopics.topic(#"{"topic":"catalog","library_id":2}"#), "catalog")
        XCTAssertNil(LiveTopics.topic("nope"))
        XCTAssertTrue(LiveTopics.touches(["catalog"], LiveTopics.home))
        XCTAssertFalse(LiveTopics.touches(["watch_together"], LiveTopics.home))
        XCTAssertTrue(LiveTopics.touches([LiveTopics.resync], LiveTopics.together))
    }

    func testHintsAreGatheredIntoOneRefresh() async {
        let got = expectation(description: "flushed")
        let seen = Box()
        let batcher = HintBatcher(firstMs: 50, spacingMs: 200) { topics in seen.add(topics); got.fulfill() }
        batcher.add("catalog")
        batcher.add("playback")
        batcher.add("catalog")
        await fulfillment(of: [got], timeout: 2)
        XCTAssertEqual(seen.all, [["catalog", "playback"]])
    }

    func testTheStreamSkipsItsFirstResyncHandsOnHintsAndResumesFromItsCursor() async {
        let body = "event: resync\nid: 1\n\n: heartbeat\n\nevent: invalidate\nid: 2\ndata: {\"topic\":\"catalog\"}\n\n"
        StubArc.answers = [.init(status: 200, body: body), .init(status: 429, body: "{}")]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubArc.self]
        let api = ArcAPI(baseURL: URL(string: "http://arc.test:8099")!, token: { "t0k" })
        let got = expectation(description: "hint")
        let seen = Box()
        let live = LiveUpdates(api: { api }, configuration: config, firstMs: 10, spacingMs: 10) { topics in
            seen.add(topics)
            got.fulfill()
        }
        live.start()
        await fulfillment(of: [got], timeout: 5)
        // Arc closed the stream; the app reopens it a second later, resuming after event 2.
        for _ in 0..<40 where StubArc.requests.count < 2 { try? await Task.sleep(nanoseconds: 100_000_000) }
        live.stop()
        XCTAssertEqual(seen.all, [["catalog"]])
        XCTAssertEqual(StubArc.requests.first?.value(forHTTPHeaderField: "Accept"), "text/event-stream")
        XCTAssertEqual(StubArc.requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer t0k")
        XCTAssertNil(StubArc.requests.first?.value(forHTTPHeaderField: "Last-Event-ID"))
        XCTAssertEqual(StubArc.requests.dropFirst().first?.value(forHTTPHeaderField: "Last-Event-ID"), "2")
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var sets: [Set<String>] = []
    func add(_ s: Set<String>) { lock.lock(); sets.append(s); lock.unlock() }
    var all: [Set<String>] { lock.lock(); defer { lock.unlock() }; return sets }
}

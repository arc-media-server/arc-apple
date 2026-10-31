import XCTest
@testable import ArcKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The client through a whole visit against a running Arc: TV sign-in code (approved as the admin,
/// as the browser would), a wrong and a right PIN, Home's rows, a show's seasons, a direct play
/// through a cast link with a ranged read, a converted stream part-way in with its playlist and
/// first segment, progress, the keep-alive ping and the session's end.
///
/// Skipped unless ARC_E2E_URL and ARC_E2E_PASSWORD are set. Use a scratch Arc, never a real one
/// (README, "Testing against a server").
final class LiveServerTests: XCTestCase {
    private let env = ProcessInfo.processInfo.environment
    private func step(_ s: String) { print("E2E: \(s)") }

    private func raw(_ base: URL, _ method: String, _ path: String, _ body: String?, token: String?) async throws -> (Int, Data) {
        var request = URLRequest(url: URL(string: base.absoluteString + "/api/v1/" + path)!)
        request.httpMethod = method
        request.httpBody = body.map { Data($0.utf8) }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, data)
    }

    private func get(_ url: URL, range: String? = nil) async throws -> (Int, Data, String) {
        var request = URLRequest(url: url)
        if let range { request.setValue(range, forHTTPHeaderField: "Range") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as! HTTPURLResponse
        return (http.statusCode, data, http.value(forHTTPHeaderField: "Content-Type") ?? "")
    }

    func testSignInBrowseAndPlay() async throws {
        guard let address = env["ARC_E2E_URL"], let password = env["ARC_E2E_PASSWORD"], let base = ServerAddress.normalize(address) else {
            throw XCTSkip("set ARC_E2E_URL and ARC_E2E_PASSWORD to run against a scratch Arc")
        }
        nonisolated(unsafe) var token: String?
        let api = ArcAPI(baseURL: base) { token }

        let health = try await api.health()
        step("health: \(health.name) \(health.version), api_version \(health.apiVersion)")
        XCTAssertEqual(health.apiVersion, 1)

        let link = try await api.startLink(device: "E2E Apple TV")
        step("sign-in code \(link.code)")
        let waiting = try await api.pollLink(link.poll)
        XCTAssertEqual(waiting, .waiting)
        // What the browser does: sign in as the admin and approve the code.
        let (_, login) = try await raw(base, "POST", "auth/login", #"{"password":"\#(password)","device":"E2E browser"}"#, token: nil)
        let admin = try XCTUnwrap((try JSONSerialization.jsonObject(with: login) as? [String: Any])?["token"] as? String)
        let adminApi = ArcAPI(baseURL: base) { admin }
        let adminId = try await adminApi.authStatus().profiles.first { $0.isAdmin }!.id
        _ = try await adminApi.chooseProfile(id: adminId, pin: nil)
        let (approve, approveBody) = try await raw(base, "POST", "auth/link/approve", #"{"code":"\#(link.code)"}"#, token: admin)
        XCTAssertTrue((200...299).contains(approve), String(decoding: approveBody, as: UTF8.self))
        guard case .approved(let deviceToken) = try await api.pollLink(link.poll) else { return XCTFail("not approved") }
        token = deviceToken
        step("approved; device token received")

        let status = try await api.authStatus()
        XCTAssertTrue(status.signedIn)
        let sam = try XCTUnwrap(status.profiles.first { $0.name == "Sam" }, "make a profile Sam with PIN 2468")
        XCTAssertTrue(sam.hasPin)
        do {
            _ = try await api.chooseProfile(id: sam.id, pin: "0000")
            XCTFail("a wrong PIN was accepted")
        } catch let error as APIError {
            XCTAssertEqual(error.needs, "pin")
            step("wrong PIN refused: \(error.status) needs \(error.needs ?? "")")
        }
        let chosen = try await api.chooseProfile(id: sam.id, pin: "2468")
        XCTAssertEqual(chosen.id, sam.id)
        let serverName = try await api.identity().name
        step("profile \(chosen.name) chosen; server name \(serverName)")

        let prefs = try await api.prefs()
        let libraries = orderedLibraries(try await api.libraries(), order: prefs.libraryOrder)
        let rows = resolveHomeRows(prefs: prefs, libraries: libraries)
        step("Home rows: \(rows.map(\.id).joined(separator: ", "))")
        let movies = try XCTUnwrap(libraries.first { $0.kind == "movies" })
        let shows = try XCTUnwrap(libraries.first { $0.kind == "shows" })
        let recentMovies = try await api.items(libraryQuery(movies, sort: "added", limit: 24)).items
        let recentShows = try await api.recentShows(libraryId: shows.id)
        step("recently added: \(recentMovies.count) movies, \(recentShows.count) show cards")
        _ = try await api.continueWatching(withUpNext: true)
        _ = try await api.watchlist()

        let showList = try await api.items(libraryQuery(shows, sort: "title", limit: 50)).items
        let series = try XCTUnwrap(showList.first)
        let seasons = try await api.seasons(seriesId: series.id)
        step("\(series.title): \(seasons.seasons.count) seasons, \(seasons.seasons.flatMap(\.episodes).count) episodes")

        // As this Apple TV plays: MP4 with H.264/HEVC and AAC/Dolby.
        let caps = PlayerCaps(containers: ["mp4"], video: ["h264", "hevc"], audio: ["aac", "mp3", "ac3", "eac3"], maxHeight: 2160)
        let movie = try XCTUnwrap(recentMovies.first)
        let full = try await api.item(movie.id)
        let plan = try await api.startPlayback(itemId: movie.id, request: PlaybackRequest(caps: caps))
        step("\(movie.title): \(plan.method) \(plan.reasons), hls=\(plan.hls), audio tracks \(plan.audioTracks.count)")
        let link1 = try await api.castLink(for: plan.url)
        if plan.hls {
            let (code, body, _) = try await get(link1)
            XCTAssertEqual(code, 200)
            XCTAssertTrue(String(decoding: body, as: UTF8.self).hasPrefix("#EXTM3U"))
        } else {
            let (code, body, _) = try await get(link1, range: "bytes=0-1023")
            XCTAssertEqual(code, 206)
            XCTAssertEqual(body.count, 1024)
            step("direct play through a cast link: 206, 1024 bytes")
        }
        if let sid = plan.sessionId { await api.stopTranscode(sid) }

        // Converted, part-way in: the playlist and its first segment, through a cast link.
        let duration = full.durationMs
        let startMs = min(60_000, duration / 2)
        let converted = try await api.startPlayback(itemId: movie.id, request: PlaybackRequest(caps: caps.fallback(after: "remux"), startMs: startMs))
        XCTAssertTrue(converted.hls)
        let sid = try XCTUnwrap(converted.sessionId)
        step("converted from \(startMs) ms: \(converted.method), offset \(converted.offsetMs) ms")
        let playlistURL = try await api.castLink(for: converted.url)
        let (pcode, pbody, _) = try await get(playlistURL)
        XCTAssertEqual(pcode, 200)
        let playlist = String(decoding: pbody, as: UTF8.self)
        let mapLine = playlist.split(separator: "\n").first { $0.hasPrefix("#EXT-X-MAP") }
        let segment = try XCTUnwrap(playlist.split(separator: "\n").first { !$0.hasPrefix("#") && !$0.isEmpty }, playlist)
        let segURL = try XCTUnwrap(URL(string: String(segment), relativeTo: playlistURL)?.absoluteURL)
        let (scode, sbody, _) = try await get(segURL)
        XCTAssertEqual(scode, 200)
        XCTAssertGreaterThan(sbody.count, 1000)
        step("playlist and first segment through the cast link: \(sbody.count) bytes; init: \(mapLine != nil)")

        try await api.reportProgress(itemId: movie.id, ProgressReport(positionMs: startMs + 5_000, durationMs: duration, state: "playing"))
        try await api.pingTranscode(sid)
        await api.stopTranscode(sid)
        try await api.reportProgress(itemId: movie.id, ProgressReport(positionMs: startMs + 5_000, durationMs: duration, state: "stopped"))
        let resumed = try await api.item(movie.id)
        XCTAssertEqual(resumed.resumeMs, startMs + 5_000)
        step("progress saved; resume point \(resumed.resumeMs) ms")
    }
}

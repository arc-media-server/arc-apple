import ArcKit
import SwiftUI

/// A page the app can open from anywhere.
enum Route: Hashable {
    case item(Item)
    case collection(id: String, title: String)
    case playlist(id: String, title: String)
    case person(id: Int64, name: String)
    case genre(GenreMatch)
    case folder(library: Library, path: String, name: String)
}

/// What every page shares: what's playing, and a count bumped when watch state changes (after
/// playing, or Mark as Watched) so pages that show it read it again.
@MainActor
@Observable
final class Browse {
    var playing: PlayRequest?
    /// A title's page to open on Home (the Top Shelf's Select); Home's stack takes it.
    var linkedRoute: Route?
    private(set) var changes = 0
    /// Watch Together: Home's rooms and the room this Apple TV is in.
    let together = WatchTogetherModel()
    /// This Apple TV's play queue, which Arc keeps (Home's Queue row), and whether the server has
    /// queues for the profile (Play Next, Add to Queue and Shuffle show only then).
    let queues = PlayQueues()
    private(set) var queue: PlayQueue?
    private(set) var queuesUsable = false
    /// Add to Playlist's list is open for this title, over the pages.
    var addingToPlaylist: Item?
    /// A short note at the top of the screen ("Added “Heat” to Movie Night"), gone after a moment.
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    func play(_ request: PlayRequest) { playing = request }
    func changed() { changes += 1 }

    /// Reads the queue Arc has for this Apple TV and profile (Home, after playing).
    func refreshQueue(_ api: ArcAPI) async {
        queuesUsable = await queues.supported(api)
        queue = queuesUsable ? await queues.refresh(api) : nil
    }

    /// Runs a queue call and shows what the queue is now.
    @discardableResult
    func withQueue<T>(_ call: (PlayQueues) async -> T) async -> T {
        let answer = await call(queues)
        queue = await queues.queue
        return answer
    }

    func note(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}

/// Opens a page on the current tab's stack.
struct OpenRoute {
    let action: (Route) -> Void
    func callAsFunction(_ route: Route) { action(route) }
}

private struct OpenRouteKey: EnvironmentKey {
    static let defaultValue = OpenRoute { _ in }
}

extension EnvironmentValues {
    var openRoute: OpenRoute {
        get { self[OpenRouteKey.self] }
        set { self[OpenRouteKey.self] = newValue }
    }
}

import ArcKit
import SwiftUI

// The title's actions and Play label, shared by Apple TV and iPhone and iPad.

/// The Play button's label. Not started: "Play" for a film, "Start watching · S1 · E1" for a
/// season's first episode, "Play S21 · E8" for any other. Part watched: a bar of how far through
/// with what's left, after the episode's number ("S5 · E12 · 43m") or alone for a film ("1h 2m").
struct PlayLabel: View {
    let item: Item
    let episode: Bool

    var body: some View {
        let resume = item.resumeMs
        let duration = item.durationMs
        let code = episode ? item.episodeCodeText : nil
        HStack(spacing: 14) {
            Image(systemName: "play.fill")
            if resume > 0, duration > resume {
                let left = Int((duration - resume + 59_999) / 60_000)
                // The bar follows the label's colour, so it shows on the white of focus too.
                ZStack(alignment: .leading) {
                    Capsule().fill(.secondary).frame(width: 70, height: 6)
                    Capsule().fill(.primary).frame(width: 70 * CGFloat(Double(resume) / Double(duration)), height: 6)
                }
                Text(code.map { L("details.resume_episode_left", $0, runtimeText(left)) } ?? runtimeText(left))
            } else if let code {
                Text(item.episodeNumber == 1 ? L("details.start_watching", code) : L("details.play_episode", code))
            } else {
                Text(L("details.play"))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// How far through: a thin rounded bar inset at the bottom of the artwork.
struct ProgressBar: View {
    let fraction: Double
    /// White on art; black on a white button.
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.3))
                Capsule().fill(color).frame(width: max(6, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
    }
}

/// A title's actions, from holding Select on its card (Plex's context menu) and on its page:
/// play, watched or not, the Watchlist, an episode's show, and taking a title out of Continue
/// Watching.
struct TitleActions: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    let item: Item
    var onPage = false
    /// The episode the series page's Play button would start.
    var versionItem: Item?
    /// Opened from a card in Continue Watching or Up Next.
    var continueRow = false
    /// Opened from this entry's card in Home's Queue row.
    var queueEntry: String?

    var body: some View {
        if !onPage && item.playable {
            Button { browse.play(PlayRequest(item: item, startMs: item.resumeMs)) } label: {
                Label(item.resumeMs > 0 ? L("details.resume") : L("details.play"), systemImage: "play.fill")
            }
            if item.resumeMs > 0 {
                Button { browse.play(PlayRequest(item: item, startMs: 0)) } label: {
                    Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise")
                }
            }
        }
        if item.playable || item.isSeries {
            Button { act("watched") { try await $0.setPlayed(item.id, !item.watched) } } label: {
                Label(item.watched ? L("actions.mark_unwatched") : L("actions.mark_watched"),
                      systemImage: item.watched ? (onPage ? "checkmark.circle.fill" : "eye.slash") : "checkmark.circle")
            }
        }
        // Out of Continue Watching and Up Next without marking it watched (an episode: its whole
        // show, until something of it plays again), as the web's card menu does.
        if continueRow && !onPage {
            Button { act("remove from continue") { try await $0.removeFromContinue(item.id) } } label: {
                Label(L("actions.remove_from_continue"), systemImage: "xmark.circle")
            }
        }
        // Rearranging the Queue row, as Android's card menu: entries after the one playing.
        if !onPage, let entry = queueEntry, let edits = browse.queue?.edits(entry) {
            if edits.earlier {
                Button { editQueue("move earlier") { await $0.move($1, entry, by: -1) } } label: {
                    Label(L("queue.move_earlier"), systemImage: "arrow.left")
                }
            }
            if edits.later {
                Button { editQueue("move later") { await $0.move($1, entry, by: 1) } } label: {
                    Label(L("queue.move_later"), systemImage: "arrow.right")
                }
            }
            if edits.remove {
                Button { editQueue("remove") { await $0.remove($1, entry) } } label: {
                    Label(L("queue.remove"), systemImage: "xmark.circle")
                }
            }
        }
        if item.kind == "movie" || item.isSeries {
            let on = item.userData?.watchlisted == true
            Button { act("watchlist") { try await $0.setWatchlisted(item.id, !on) } } label: {
                Label(on ? L("actions.watchlist_remove") : L("actions.watchlist_add"), systemImage: on ? "bookmark.slash" : "bookmark")
            }
        }
        // A card's menu lists them all; the page keeps them in its ⋯ menu, as Plex's and Android's.
        if !onPage {
            PlayVersionMenu(item: item, queueEntry: queueEntry)
            queueAndPlaylist
        } else if queueable {
            Menu {
                PlayVersionMenu(item: versionItem ?? item)
                queueAndPlaylist
                // The profile's own stars, on the title's page (as the web's StarRating).
                rate
            } label: {
                Label(L("actions.more"), systemImage: "ellipsis")
            }
        }
        if item.kind == "movie" || item.isEpisode {
            Button { browse.together.inviting = .init(itemId: item.id, title: item.title) } label: {
                Label(L("together.menu"), systemImage: "person.2")
            }
        }
        if !onPage, item.isEpisode, let show = item.parentId {
            Button { openRoute(.item(Item(id: show, kind: "series", title: item.seriesTitle ?? item.title))) } label: {
                Label(L("actions.go_to_show"), systemImage: "tv")
            }
        }
    }

    /// Films, episodes and whole shows: what queues and playlists hold, and what can be rated.
    private var queueable: Bool { item.kind == "movie" || item.isEpisode || item.isSeries }

    @ViewBuilder private var queueAndPlaylist: some View {
        if queueable {
            if browse.queuesUsable {
                Button { addToQueue(next: true) } label: {
                    Label(L("actions.play_next"), systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                Button { addToQueue(next: false) } label: {
                    Label(L("actions.add_to_queue"), systemImage: "text.append")
                }
            }
            Button { browse.addingToPlaylist = item } label: {
                Label(L("actions.add_to_playlist"), systemImage: "text.badge.plus")
            }
        }
    }

    /// Moves or removes a Queue row entry; Home's row follows the queue Arc answers with.
    private func editQueue(_ what: String, _ call: @escaping (PlayQueues, ArcAPI) async -> PlayQueue?) {
        guard let api = app.api else { return }
        Task {
            let q = await browse.withQueue { await call($0, api) }
            if q == nil { browse.note(L("queue.edit_failed")) } else { ArcLogApp.debug("title action done: queue \(what)") }
        }
    }

    /// Play Next or Add to Queue (a show adds its episodes); with no queue yet, it starts one
    /// without playing, and Home's Queue row appears.
    private func addToQueue(next: Bool) {
        guard let api = app.api else { return }
        let item = item, browse = browse
        Task {
            let q = await browse.withQueue { await $0.add(api, [item.id], next: next) }
            if q != nil { ArcLogApp.debug("title action done: \(next ? "play next" : "add to queue")") }
            browse.note(q == nil ? L("queue.failed", item.title) : L(next ? "queue.playing_next" : "queue.added", item.title))
        }
    }

    /// Rate…: five stars in halves, best first, the current one ticked, and Clear Rating.
    private var rate: some View {
        let current = item.userData?.rating ?? 0
        return Menu {
            Section(L("rating.title")) {
                ForEach(StarRating.choices, id: \.self) { r in
                    let text = L("rating.choice", StarRating.stars(r) ?? "", StarRating.outOfFive(r))
                    Button { setRating(r) } label: {
                        if r == current { Label(text, systemImage: "checkmark") } else { Text(text) }
                    }
                }
                if current > 0 {
                    Button { setRating(0) } label: { Label(L("rating.clear"), systemImage: "xmark") }
                }
            }
        } label: {
            Label(StarRating.stars(current).map { L("rating.rated", $0) } ?? L("actions.rate"),
                  systemImage: current > 0 ? "star.fill" : "star")
        }
    }

    private func setRating(_ rating: Int) {
        act(rating == 0 ? "rating cleared" : "rating") { try await $0.setRating(item.id, rating) }
    }

    private func act(_ what: String, _ call: @escaping (ArcAPI) async throws -> Void) {
        guard let api = app.api else { return }
        Task {
            do {
                try await call(api)
                ArcLogApp.debug("title action done: \(what)")
                browse.changed()
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("title action \(what) failed: \(type(of: error))")
            }
        }
    }
}

/// Play one of several on-disk versions from the title's current resume point.
struct PlayVersionMenu: View {
    @Environment(Browse.self) private var browse
    let item: Item
    var queueEntry: String?

    var body: some View {
        if item.playable && item.available {
            let files = item.files.filter { !$0.missing && $0.part <= 1 }
            if files.count > 1 {
                let labels = Dictionary(grouping: files, by: versionLabel)
                Menu {
                    ForEach(files) { file in
                        let label = versionLabel(file)
                        let title = label.isEmpty || (labels[label]?.count ?? 0) > 1 ? fileLabel(file, version: label) : label
                        Button(title) {
                            browse.play(PlayRequest(item: item, startMs: item.resumeMs, queueEntry: queueEntry, fileId: file.id))
                        }
                    }
                } label: {
                    Label(L("details.play_version"), systemImage: "film")
                }
            }
        }
    }

    private func versionLabel(_ file: MediaFile) -> String {
        let video = file.streams.first { $0.kind == "video" }
        return Version(fileId: file.id, edition: file.edition, width: video?.width, height: video?.height,
                       videoCodec: video?.codec, hdr: video.flatMap { Quality.hdr($0) }, size: file.size ?? 0).label
    }

    private func fileLabel(_ file: MediaFile, version: String) -> String {
        let filename = file.path?.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init)
        let name = filename ?? L("details.file_number", String(file.id))
        return version.isEmpty ? name : "\(version) · \(name)"
    }
}

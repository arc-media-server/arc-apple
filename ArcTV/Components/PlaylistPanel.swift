import ArcKit
import SwiftUI

/// Add to Playlist: the profile's playlists, each with how many titles it holds. Smart playlists
/// fill themselves, so they aren't listed (as the web's picker). Choosing one adds the title,
/// closes the list and says so at the top of the screen. Playlists are made on the web.
struct PlaylistPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    let item: Item
    @State private var playlists: [PlaylistSummary]?
    @State private var failed = false
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("playlist_add.title")).font(.title3.weight(.bold))
                    Text(L(item.isSeries ? "playlist_add.body_show" : "playlist_add.body", item.title))
                        .font(.callout).foregroundStyle(ArcColor.muted)
                }
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let playlists {
                            if playlists.isEmpty {
                                Text(L("playlist_add.none")).font(.callout).foregroundStyle(ArcColor.muted)
                            }
                            ForEach(playlists) { row($0) }
                        } else if failed {
                            Text(L("playlist_add.load_failed")).font(.callout).foregroundStyle(ArcColor.muted)
                            Button(L("common.retry")) { Task { await load() } }.arcGlassButton()
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .focusSection()
                Button(L("common.close")) { browse.addingToPlaylist = nil }.arcGlassButton()
            }
            .padding(40)
            .frame(width: 680)
            .frame(maxHeight: .infinity)
            .arcGlassPanel(cornerRadius: 40)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
            .padding(.vertical, 60)
            .padding(.trailing, 60)
        }
        .onExitCommand { browse.addingToPlaylist = nil }
        .task { await load() }
    }

    private func row(_ list: PlaylistSummary) -> some View {
        Button { add(to: list) } label: {
            HStack(spacing: 20) {
                Image(systemName: "list.bullet.rectangle").font(.title3)
                Text(list.title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Text(L("playlist_add.count", list.count)).font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
        .arcGlassButton()
        .buttonBorderShape(.capsule)
        .disabled(busy)
    }

    private func load() async {
        guard let api = app.api else { return }
        failed = false
        do {
            playlists = try await api.playlists().filter(\.editable)
        } catch let error as APIError where error.status == 401 {
            app.tokenRefused()
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("playlists failed to load for Add to Playlist: \(type(of: error))")
            failed = true
        }
    }

    private func add(to list: PlaylistSummary) {
        guard let api = app.api else { return }
        busy = true
        let item = item
        Task {
            do {
                try await api.addToPlaylist(list.id, itemIds: [item.id])
                ArcLogApp.debug("title action done: added to a playlist")
                browse.note(L("playlist_add.added", item.title, list.title))
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("adding to a playlist failed: \(type(of: error))")
                browse.note(L("playlist_add.failed", item.title))
            }
            busy = false
            browse.addingToPlaylist = nil
        }
    }
}

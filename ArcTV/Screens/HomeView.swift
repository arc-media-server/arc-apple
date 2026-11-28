import ArcKit
import SwiftUI

/// Home: the focused title's hero over the profile's rows (HeroRows).
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var model = HomeModel()

    var body: some View {
        Group {
            if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.failed {
                RowsMessage(title: L("home.failed_title"), message: L("common.unreachable")) { Task { await reload() } }
            } else if model.rows.isEmpty {
                RowsMessage(title: L("home.empty_title"), message: L("home.empty_body"), retry: nil)
            } else {
                HeroRows(rows: model.rows + queueRow, top: browse.together.rooms.isEmpty ? nil : { focus in AnyView(WatchTogetherRow(focus: focus)) })
            }
        }
        // Read again after playing or a change of watch state, so Continue Watching is current.
        .task(id: browse.changes) { await reload() }
        // Live updates: the rows reload in place (never under the player; Home reads them again
        // after playing anyway). Watch Together's rooms follow their own hint (MainView).
        .onChange(of: app.liveHome) { if browse.playing == nil { Task { await reload() } } }
    }

    /// The play queue, after everything else (as on Android): the title playing and what follows.
    private var queueRow: [LoadedRow] {
        let entries = browse.queue?.upcoming() ?? []
        guard !entries.isEmpty else { return [] }
        let cards = entries.compactMap { e in e.item.map { MediaCard(item: $0, id: e.id) } }
        return [LoadedRow(id: "queue", title: L("home.queue"), style: .poster, cards: cards, queueRow: true)]
    }

    private func reload() async {
        guard let api = app.api else { return }
        await browse.refreshQueue(api)
        // The rooms first: a Watch Together row arriving just after the rows took the focus
        // away from the first card (tvOS gave it to the sidebar).
        await browse.together.refreshRooms(api)
        await model.load(api) { app.tokenRefused() }
    }
}

/// What a page of rows says when it has none, or couldn't load them.
struct RowsMessage: View {
    let title: String
    let message: String
    let retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 20) {
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: 900)
            if let retry { Button(L("common.retry"), action: retry).arcGlassButton() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

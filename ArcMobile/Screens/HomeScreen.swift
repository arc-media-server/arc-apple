import ArcKit
import SwiftUI

/// Home: the profile's rows as arranged on the web (Edit Home, Arrange libraries), the same rows
/// as the Apple TV's, each scrolling sideways; the play queue's row last. Pull down to refresh.
struct MobileHomeScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @State private var model = HomeModel()

    var body: some View {
        Group {
            if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.failed {
                MobileMessage(title: L("home.failed_title"), message: L("common.unreachable")) { Task { await reload() } }
            } else if model.rows.isEmpty {
                MobileMessage(title: L("home.empty_title"), message: L("home.empty_body"))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(model.rows + queueRow) { row in
                            MobileRow(title: row.title, cards: row.cards, style: row.style, seasonPosters: row.seasonPosters,
                                      continueRow: row.continueRow, queueRow: row.queueRow, showsLength: false)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .refreshable { await reload() }
            }
        }
        .navigationTitle(L("tab.home"))
        .background(PageWash())
        // Read again after playing or a change of watch state, so Continue Watching is current.
        .task(id: browse.changes) { await reload() }
        .onChange(of: app.liveHome) { if browse.playing == nil { Task { await reload() } } }
    }

    /// The play queue, after everything else (as on Android and Apple TV).
    private var queueRow: [LoadedRow] {
        let entries = browse.queue?.upcoming() ?? []
        guard !entries.isEmpty else { return [] }
        let cards = entries.compactMap { e in e.item.map { MediaCard(item: $0, id: e.id) } }
        return [LoadedRow(id: "queue", title: L("home.queue"), style: .poster, cards: cards, queueRow: true)]
    }

    private func reload() async {
        guard let api = app.api else { return }
        await browse.refreshQueue(api)
        await model.load(api) { app.tokenRefused() }
    }
}

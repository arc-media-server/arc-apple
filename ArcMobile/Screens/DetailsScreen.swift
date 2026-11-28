import ArcKit
import SwiftUI

/// A title's page, as iOS shows one (Apple's TV app, Plex for iOS): the artwork across the top
/// fading into the page's colours, the logo or name, the details line, a full-width Play, the
/// actions under ⋯ in the bar, the overview; a show's seasons and episodes; then the cast and
/// More Like This.
struct MobileDetailsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.openRoute) private var openRoute
    @Environment(\.horizontalSizeClass) private var sizeClass
    let itemId: String
    let initial: Item
    /// Opened from an episode's card: the show's page opens on that episode's season.
    var episodeId: String? = nil

    @State private var item: Item?
    @State private var similar: [Item] = []
    @State private var seasons: [Season] = []
    @State private var season = 0
    @State private var keepSeason: Int?
    @State private var landed = false
    @State private var problem: String?
    @State private var wash: [Color]?
    @State private var overviewOpen = false

    private var shown: Item { item ?? initial }
    private var wide: Bool { sizeClass == .regular }
    private var backdropPath: String? { shown.images?.backdrop ?? shown.images?.seriesBackdrop }
    private var paletteSource: String? {
        shown.images?.backdrop != nil ? shown.id : (shown.images?.seriesBackdrop != nil ? shown.parentId : shown.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 16) {
                    playButtons
                    if let overview = shown.overview(hidingSpoilers: app.hideSpoilers) {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundStyle(ArcColor.foreground.opacity(0.85))
                            .lineLimit(overviewOpen ? nil : 4)
                            .onTapGesture { withAnimation { overviewOpen.toggle() } }
                    }
                    if let problem { Text(problem).font(.footnote).foregroundStyle(ArcColor.error) }
                }
                .padding(.horizontal, Metrics.margin(wide))
                .frame(maxWidth: wide ? 720 : .infinity, alignment: .leading)
                if shown.isSeries && !seasons.isEmpty { episodes.padding(.top, 28) }
                cast.padding(.top, 28)
                if !similar.isEmpty {
                    MobileRow(title: L("details.more_like_this"), cards: similar.map { MediaCard(item: $0) }, style: .poster)
                        .padding(.top, 28)
                }
            }
            .padding(.bottom, 32)
        }
        .ignoresSafeArea(edges: .top)
        .background(PageWash(colors: wash))
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    TitleActions(item: shown, versionItem: nextEpisode)
                } label: {
                    Label(L("actions.more"), systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("details.more")
            }
        }
        .task(id: browse.changes) { await load() }
        .task(id: paletteSource) {
            guard let id = paletteSource, let api = app.api,
                  let colors = try? await api.palette(id).background else { return }
            wash = colors.map(Color.init)
        }
        .onChange(of: app.liveTitle) { if browse.playing == nil { Task { await load() } } }
    }

    // MARK: The top

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .aspectRatio(wide ? 21.0 / 9.0 : 4.0 / 3.0, contentMode: .fit)
                .overlay { ArtworkImage(path: backdropPath, placeholder: .clear) }
                .clipped()
                // The artwork fades into the page's colours at the bottom.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.55),
                                             .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 8) {
                TitleLogo(path: shown.isEpisode ? shown.images?.seriesLogo : shown.images?.logo,
                          title: shown.isEpisode ? shown.seriesTitle ?? shown.title : shown.title,
                          maxWidth: wide ? 360 : 240, maxHeight: wide ? 110 : 80, fontSize: wide ? 36 : 28)
                if shown.isEpisode { Text(shown.episodeLine).font(.headline) }
                metaLine
            }
            .padding(.horizontal, Metrics.margin(wide))
            .padding(.bottom, 12)
        }
    }

    /// "2008 · PG-13 · 2h 32m · Action, Crime", as the TV's hero line.
    private var metaLine: some View {
        HStack(spacing: 8) {
            if let year = shown.yearAndEdition { Text(year) }
            if let rating = shown.contentRating, !rating.isEmpty {
                Text(rating)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(ArcColor.foreground.opacity(0.85), lineWidth: 1))
            }
            if let m = shown.runtimeMin, m > 0 { Text(runtimeText(m)) }
            if !shown.genres.isEmpty { Text(shown.genres.prefix(2).joined(separator: ", ")).lineLimit(1) }
        }
        .font(.footnote)
        .foregroundStyle(ArcColor.muted)
    }

    @ViewBuilder private var playButtons: some View {
        let target: Item? = shown.playable ? shown : nextEpisode
        if let target {
            VStack(spacing: 10) {
                Button { browse.play(PlayRequest(item: target, startMs: target.resumeMs)) } label: {
                    PlayLabel(item: target, episode: target.isEpisode).frame(maxWidth: .infinity)
                }
                .arcGlassButton(prominent: true)
                .controlSize(.large)
                .accessibilityIdentifier("details.play")
                HStack(spacing: 10) {
                    if target.resumeMs > 0 {
                        Button { browse.play(PlayRequest(item: target, startMs: 0)) } label: {
                            Label(L("details.from_beginning"), systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                        }
                        .arcGlassButton()
                    }
                    if shown.isSeries && browse.queuesUsable && shuffleCandidates(nil).count > 1 {
                        Button { shuffle(nil) } label: {
                            Label(L("details.shuffle"), systemImage: "shuffle").frame(maxWidth: .infinity)
                        }
                        .arcGlassButton()
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    // MARK: Seasons and episodes

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if seasons.count > 1 {
                    Menu {
                        Picker("", selection: $season) {
                            ForEach(Array(seasons.enumerated()), id: \.offset) { i, s in
                                Text(seasonName(s)).tag(i)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(seasons.indices.contains(season) ? seasonName(seasons[season]) : "")
                            Image(systemName: "chevron.down").font(.footnote.weight(.semibold))
                        }
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ArcColor.foreground)
                    }
                    .accessibilityIdentifier("details.season")
                } else if let only = seasons.first {
                    Text(seasonName(only)).font(.title3.weight(.bold))
                }
                Spacer()
                if seasons.indices.contains(season), seasons[season].markable {
                    let s = seasons[season]
                    Menu {
                        Button { markSeason(s, watched: !s.watched) } label: {
                            Label(s.watched ? L("actions.mark_unwatched") : L("actions.season_watched"),
                                  systemImage: s.watched ? "eye.slash" : "checkmark.circle")
                        }
                        if browse.queuesUsable && shuffleCandidates(s).count > 1 {
                            Button { shuffle(s) } label: { Label(L("actions.shuffle_season"), systemImage: "shuffle") }
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(Text(L("actions.more")))
                }
            }
            .padding(.horizontal, Metrics.margin(wide))
            if seasons.indices.contains(season) {
                let s = seasons[season]
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(s.episodes) { ep in
                        MobileEpisodeRow(episode: ep, unplaced: s.isUnplaced)
                    }
                }
                .padding(.horizontal, Metrics.margin(wide))
            }
        }
    }

    private func seasonName(_ s: Season) -> String {
        s.name.isEmpty ? L("details.season", s.seasonNumber) : s.name
    }

    // MARK: Cast

    @ViewBuilder private var cast: some View {
        let people = shown.credits.filter { $0.role == "actor" || $0.role.isEmpty }
        if !people.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("details.starring")).font(.title3.weight(.bold)).padding(.horizontal, Metrics.margin(wide))
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(people) { c in
                            MobilePersonButton(name: c.name, detail: c.character, image: c.image) {
                                openRoute(.person(id: c.personId, name: c.name))
                            }
                        }
                    }
                }
                .contentMargins(.horizontal, Metrics.margin(wide), for: .scrollContent)
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Loading and actions

    /// A show's Play: the first episode not yet watched (or part-watched), else the first, in the
    /// show's order (as the TV's page).
    private var nextEpisode: Item? {
        let all = seasons.filter { $0.seasonNumber > 0 }.flatMap(\.episodes) + seasons.filter { $0.seasonNumber == 0 }.flatMap(\.episodes)
        let available = all.filter(\.available)
        return available.first { !$0.watched } ?? available.first
    }

    private func shuffleCandidates(_ s: Season?) -> [Item] {
        if let s { return s.isUnplaced ? [] : s.episodes.filter(\.available) }
        let ordered = seasons.filter { $0.seasonNumber > 0 } + seasons.filter { $0.seasonNumber == 0 }
        return ordered.flatMap(\.episodes).filter(\.available)
    }

    private func shuffle(_ s: Season?) {
        guard let api = app.api else { return }
        let ids = shuffleCandidates(s).map(\.id)
        let browse = browse
        Task {
            let entry = await browse.withQueue { await $0.startShuffled(api, ids) }
            guard let entry, let first = entry.item else {
                ArcLogApp.warn("shuffling \(s == nil ? "a show" : "a season") failed")
                browse.note(L("queue.shuffle_failed"))
                return
            }
            ArcLogApp.debug("shuffled \(ids.count) episodes")
            browse.play(PlayRequest(item: first, startMs: 0, queueEntry: entry.id))
        }
    }

    private func markSeason(_ s: Season, watched: Bool) {
        guard let api = app.api else { return }
        let id = itemId
        Task {
            do {
                try await api.setPlayed(seriesId: id, seasonNumber: s.seasonNumber, watched)
                keepSeason = s.seasonNumber
                ArcLogApp.debug("title action done: season \(watched ? "watched" : "unwatched")")
                browse.changed()
            } catch let error as APIError where error.status == 401 {
                app.tokenRefused()
            } catch {
                ArcLogApp.warn("title action season watched failed: \(type(of: error))")
            }
        }
    }

    private func load() async {
        guard let api = app.api else { return }
        if seasons.indices.contains(season) && keepSeason == nil { keepSeason = seasons[season].seasonNumber }
        do {
            item = try await api.item(itemId)
            problem = nil
            if !shown.isEpisode {
                similar = (try? await api.similar(itemId)) ?? similar
            }
            if shown.isSeries {
                seasons = try await api.seasons(seriesId: itemId, missing: app.showMissingEpisodes).tabs(unplacedName: L("details.not_in_order"))
                if !landed, let id = episodeId, let at = seasons.firstIndex(where: { $0.episodes.contains { $0.id == id } }) {
                    landed = true
                    keepSeason = nil
                    season = at
                } else if let kept = keepSeason, let at = seasons.firstIndex(where: { $0.seasonNumber == kept }) {
                    keepSeason = nil
                    season = at
                } else if let next = nextEpisode, let at = seasons.firstIndex(where: { $0.seasonNumber == next.seasonNumber }) {
                    season = at
                }
            }
        } catch let error as APIError where error.status == 401 {
            app.tokenRefused()
        } catch is CancellationError {
        } catch {
            ArcLogApp.warn("title page failed to load: \(type(of: error))")
            problem = L("common.unreachable")
        }
    }
}

/// An episode in a season, as iOS lists them (Apple's TV app): its still with how far through,
/// its number and name, its length, and its overview under them. A tap plays it; touching and
/// holding gives its actions. One not out yet is dimmed with the day it releases.
struct MobileEpisodeRow: View {
    @Environment(AppModel.self) private var app
    @Environment(Browse.self) private var browse
    @Environment(\.horizontalSizeClass) private var sizeClass
    let episode: Item
    var unplaced = false

    var body: some View {
        let wide = sizeClass == .regular
        let release = episode.upcomingRelease()
        Button {
            guard episode.available else { return }
            browse.play(PlayRequest(item: episode, startMs: episode.resumeMs))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                let hidden = episode.spoilerHidden(app.hideSpoilers)
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(width: wide ? 220 : 148)
                    .overlay {
                        ArtworkImage(path: episode.images?.primary)
                            .blur(radius: hidden ? 12 : 0)
                    }
                    .overlay(alignment: .bottom) {
                        if let p = MediaCard(item: episode).progress { MobileProgressBar(fraction: p).padding(6) }
                    }
                    .overlay(alignment: .topTrailing) { MobileWatchBadge(item: episode) }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(unplaced ? episode.title : episode.episodeLine)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ArcColor.foreground)
                        .lineLimit(2)
                    if let release {
                        Text(L("details.releases", Item.releaseDay(release))).font(.caption).foregroundStyle(ArcColor.muted)
                    } else if !episode.available {
                        Text(L("details.not_on_disk")).font(.caption).foregroundStyle(ArcColor.muted)
                    } else if let m = episode.runtimeMin, m > 0 {
                        Text(runtimeText(m)).font(.caption).foregroundStyle(ArcColor.muted)
                    }
                    if let overview = episode.overview(hidingSpoilers: app.hideSpoilers) {
                        Text(overview).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(wide ? 3 : 2)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .opacity(episode.available ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { TitleActions(item: episode) }
    }
}

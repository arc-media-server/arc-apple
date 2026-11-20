import ArcKit
import Foundation
import TVServices

/// The Top Shelf (the row above the app on the Home Screen when Arc is in the top row): the
/// profile's most recent Continue Watching titles, as Arc's Home lists them, with how far
/// through each is. Select opens the title in Arc; Play plays it.
///
/// tvOS fetches the pictures itself and can't send Arc's sign-in header, so they're downloaded
/// here into the app group's container and handed over as files.
final class ContentProvider: TVTopShelfContentProvider {
    private static let limit = 10
    private let log = ArcLog.shared

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        Task {
            completionHandler(await content())
        }
    }

    private func content() async -> TVTopShelfContent? {
        // Not set up yet, or signed out: tvOS shows the app's own picture instead.
        guard let server = Shared.server(), let token = Keychain.read() else { return nil }
        let api = ArcAPI(baseURL: server, token: { token })
        let started = Date()
        let items: [Item]
        do {
            items = Array(try await api.continueWatching(withUpNext: true).prefix(Self.limit))
        } catch {
            log.warn("top shelf: Continue Watching unavailable (\(type(of: error)))")
            return nil
        }
        guard !items.isEmpty else { return nil }
        let folder = Shared.shelfFolder()
        var shelf: [TVTopShelfSectionedItem] = []
        var pictures = 0
        var kept: Set<String> = []
        for item in items {
            let entry = TVTopShelfSectionedItem(identifier: item.id)
            // An episode outside its show's order has no "S0 · E0": the show and the episode's name.
            let show = item.seriesTitle ?? item.title
            switch item.episodeCode {
            case .numbered(let season, let number)?:
                entry.title = String(format: NSLocalizedString("topshelf.episode", comment: ""), show, season, number)
            case .special(let number)?:
                entry.title = String(format: NSLocalizedString("topshelf.special", comment: ""), show, number)
            case nil:
                entry.title = item.isEpisode
                    ? String(format: NSLocalizedString("topshelf.episode_unnumbered", comment: ""), show, item.title)
                    : item.title
            }
            entry.imageShape = .hdtv
            if let folder, let file = await picture(for: item, api: api, in: folder) {
                entry.setImageURL(file, for: .screenScale1x)
                entry.setImageURL(file, for: .screenScale2x)
                kept.insert(file.lastPathComponent)
                pictures += 1
            }
            if item.durationMs > 0, item.resumeMs > 0 {
                entry.playbackProgress = min(1, Double(item.resumeMs) / Double(item.durationMs))
            }
            if let open = Shared.url(.open(item.id)) { entry.displayAction = TVTopShelfAction(url: open) }
            if let play = Shared.url(.play(item.id)) { entry.playAction = TVTopShelfAction(url: play) }
            shelf.append(entry)
        }
        if let folder { tidy(folder, keeping: kept) }
        let section = TVTopShelfItemCollection(items: shelf)
        section.title = NSLocalizedString("topshelf.continue", comment: "")
        log.info("top shelf: \(shelf.count) titles, \(pictures) pictures in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
        return TVTopShelfSectionedContent(sections: [section])
    }

    /// The card's picture as Home shows it (an episode's show art, else the title's wide
    /// picture), saved as a file tvOS can read.
    private func picture(for item: Item, api: ArcAPI, in folder: URL) async -> URL? {
        let card = MediaCard(item: item).withShowArt()
        guard let path = card.thumb ?? item.images?.backdrop ?? item.images?.primary, let url = api.absolute(path) else { return nil }
        var request = URLRequest(url: url)
        for (name, value) in api.authorization { request.setValue(value, forHTTPHeaderField: name) }
        let file = folder.appendingPathComponent(Self.fileName(item.id))
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
            try data.write(to: file, options: .atomic)
            return file
        } catch {
            log.debug("top shelf: a picture failed (\(type(of: error)))")
            // Last time's copy is better than none.
            return FileManager.default.fileExists(atPath: file.path) ? file : nil
        }
    }

    /// Pictures of titles no longer on the shelf go.
    private func tidy(_ folder: URL, keeping kept: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// A file name from an item id ("ep:12:tvdb:345" has characters a name shouldn't).
    static func fileName(_ id: String) -> String {
        String(id.map { $0.isLetter || $0.isNumber ? $0 : "_" }) + ".jpg"
    }
}

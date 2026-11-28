import ArcKit
import SwiftUI
import UIKit

/// Loads Arc's artwork with the device's sign-in (AsyncImage can't send it), keeping recent
/// pictures in memory.
actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private var running: [URL: Task<UIImage?, Never>] = [:]

    init() { cache.totalCostLimit = 200 * 1024 * 1024 }

    func image(_ url: URL, headers: [String: String]) async -> UIImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = running[url] { return await task.value }
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil }
            return image.preparingForDisplay() ?? image
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)) }
        return image
    }
}

/// A picture from Arc, filling its frame; a plain surface until (or unless) it loads.
struct ArtworkImage: View {
    @Environment(AppModel.self) private var app
    let path: String?
    var contentMode: ContentMode = .fill
    /// What shows until (or unless) it loads; logos over art use clear.
    var placeholder: Color = ArcColor.surface2
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
        }
        .task(id: path) {
            guard let path, let api = app.api, let url = api.absolute(path) else {
                image = nil
                return
            }
            image = await ArtworkLoader.shared.image(url, headers: api.authorization)
        }
    }
}

/// A title's logo, or its name when there's no logo or it can't be loaded (never an empty box).
struct TitleLogo: View {
    @Environment(AppModel.self) private var app
    let path: String?
    let title: String
    /// The logo's room, and the name's size without one (the TV's sizes unless given).
    var maxWidth: CGFloat = 640
    var maxHeight: CGFloat = 200
    var fontSize: CGFloat = 64
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack(alignment: .leading) {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
            } else if failed || path == nil {
                Text(title).font(.system(size: fontSize, weight: .bold))
            } else {
                // Loading: keep the logo's room so the page doesn't jump when it arrives.
                Color.clear.frame(width: maxWidth, height: maxHeight)
            }
        }
        .task(id: path) {
            image = nil
            failed = false
            guard let path, let api = app.api, let url = api.absolute(path) else {
                failed = true
                return
            }
            image = await ArtworkLoader.shared.image(url, headers: api.authorization)
            failed = image == nil
        }
    }
}

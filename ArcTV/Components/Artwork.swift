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
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                ArcColor.surface2
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

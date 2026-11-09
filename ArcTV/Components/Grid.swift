import ArcKit
import SwiftUI

/// Titles as a grid of posters (a library, a collection, a person's titles…). Opening a title
/// shows its page; `more` is asked for when the last row comes into view, for paging.
struct TitleGrid: View {
    let items: [Item]
    var more: (() -> Void)?
    @Environment(\.openRoute) private var openRoute
    @FocusState private var focused: String?

    static let columns = [GridItem(.adaptive(minimum: CardStyle.poster.size.width, maximum: CardStyle.poster.size.width), spacing: 28, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 56) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MediaCardView(card: MediaCard(item: item), style: .poster, focus: $focused, focusKey: item.id) { openRoute(.item(item)) }
                    .onAppear { if index >= items.count - 12 { more?() } }
            }
        }
    }
}

/// A picture with a name under it, for collections, playlists and folders in a grid.
struct TileButton: View {
    let title: String
    var subtitle: String?
    let art: String?
    var wide = false
    let action: () -> Void

    var body: some View {
        let size = wide ? CardStyle.thumb.size : CardStyle.poster.size
        VStack(alignment: .leading, spacing: 10) {
            Button(action: action) {
                ZStack {
                    ArtworkImage(path: art).frame(width: size.width, height: size.height).clipped()
                    if art == nil {
                        Text(title).font(.headline).multilineTextAlignment(.center).padding(16)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cardCorner, style: .continuous))
            }
            .buttonStyle(.card)
            Text(title).font(.callout.weight(.semibold)).lineLimit(1).frame(width: size.width, alignment: .leading)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(ArcColor.muted).lineLimit(1) }
        }
    }
}

/// A page's title and what's on it, or a message when there's nothing (never a blank page).
struct PageScaffold<Content: View>: View {
    let title: String
    var loading = false
    var problem: String?
    var empty: String?
    /// Controls at the right of the title (the Watchlist's filter and sort).
    var accessory: AnyView?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .center, spacing: 24) {
                    Text(title).font(.title2.weight(.semibold))
                    Spacer(minLength: 0)
                    if let accessory { accessory }
                }
                .focusSection()
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 400)
                } else if let problem {
                    Text(problem).foregroundStyle(ArcColor.error).frame(maxWidth: .infinity, minHeight: 400)
                } else if let empty {
                    Text(empty).foregroundStyle(ArcColor.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 400)
                } else {
                    content()
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 40)
        }
    }
}

/// Loads a page's answer from Arc: 401 asks for a new sign-in; another failure is logged and
/// comes back as the message to show (`problem`); a cancelled load comes back as neither.
@MainActor
func loadPage<T>(_ app: AppModel, _ what: String, _ load: (ArcAPI) async throws -> T) async -> (value: T?, problem: String?) {
    guard let api = app.api else { return (nil, nil) }
    do {
        return (try await load(api), nil)
    } catch let error as APIError where error.status == 401 {
        app.tokenRefused()
    } catch is CancellationError {
    } catch let error as URLError where error.code == .cancelled {
    } catch {
        ArcLogApp.warn("\(what) failed to load: \(type(of: error))")
        return (nil, L("common.unreachable"))
    }
    return (nil, nil)
}

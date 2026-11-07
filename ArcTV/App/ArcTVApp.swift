import SwiftUI

@main
struct ArcTVApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }
}

/// One screen at a time, in the order a new Apple TV meets them: the server, signing in, the
/// profile picker, then Home and the other tabs.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            PageWash()
            switch app.stage {
            case .launching: ProgressView()
            case .server: ServerView()
            case .signIn: SignInView()
            case .profiles: ProfilesView()
            case .home: MainView()
            }
        }
        .task { await app.launch() }
        // The Top Shelf's Select (open the title) and Play.
        .onOpenURL { url in
            if let link = Shared.link(url) { app.pendingLink = link }
        }
    }
}

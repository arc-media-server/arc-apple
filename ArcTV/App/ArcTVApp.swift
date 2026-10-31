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
/// profile picker, then Home.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            ArcColor.background.ignoresSafeArea()
            switch app.stage {
            case .launching: ProgressView()
            case .server: ServerView()
            case .signIn: SignInView()
            case .profiles: ProfilesView()
            case .home: HomeView()
            }
        }
        .task { await app.launch() }
    }
}

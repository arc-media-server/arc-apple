import ArcKit
import SwiftUI

/// Arc for iPhone and iPad: the same server, sign-in, data and player as the Apple TV app, with
/// screens that follow iOS's own conventions (tab bar, navigation stacks, sheets, touch controls)
/// in Arc's dark, colourless look.
@main
struct ArcMobileApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var delegate
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            MobileRoot()
                .environment(app)
                .preferredColorScheme(.dark)
                // Arc has no UI colour: chosen and main controls are white (owner, 1 November).
                .tint(ArcColor.foreground)
        }
    }
}

/// One screen at a time, as on Apple TV: the server, signing in, who's watching, then the tabs.
struct MobileRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            ArcColor.background.ignoresSafeArea()
            switch app.stage {
            case .launching: ProgressView()
            case .server: MobileServerScreen()
            case .signIn: MobileSignInScreen()
            case .profiles: MobileProfilesScreen()
            case .home: MobileTabs()
            }
        }
        .task { await app.launch() }
        .onOpenURL { url in
            if let link = Shared.link(url) { app.pendingLink = link }
        }
    }
}

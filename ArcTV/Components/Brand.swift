import ArcKit
import SwiftUI

// Arc's look on the first screens, shared by Apple TV and iPhone and iPad.

/// The soft light behind the server, sign-in and profile screens, as the web's and Android's:
/// a large white glow above the middle of the screen, fading to the page colour.
struct AuthGlow: View {
    /// How far the glow reaches (the TV's unless given).
    var radius: CGFloat = 1100

    var body: some View {
        ZStack {
            ArcColor.background
            RadialGradient(colors: [ArcColor.foreground.opacity(0.18), ArcColor.foreground.opacity(0.06), .clear],
                           center: UnitPoint(x: 0.5, y: -0.11), startRadius: 0, endRadius: radius)
        }
        .ignoresSafeArea()
    }
}

/// Arc's logo (arc-media-server `docs/brand`, chosen 13 November): white, no colour. The main
/// logo (the TV beside "arc / MEDIA SERVER") tops the server, sign-in and profile screens, as on
/// Android; the stacked one (the TV above the name) is for About.
struct ArcWordmark: View {
    var stacked = false
    /// The TV's sizes unless given (iPhone and iPad pass their own).
    var height: CGFloat? = nil

    var body: some View {
        Image(stacked ? "ArcLogoStacked" : "ArcLogo")
            .resizable()
            .scaledToFit()
            .frame(height: height ?? (stacked ? 220 : 88))
            .accessibilityLabel(Text(L("about.product_name")))
    }
}

/// A profile's picture: its initial on its colour (web/src/components/Avatar.tsx).
struct Avatar: View {
    let name: String
    let color: String
    let size: CGFloat

    init(profile: Profile, size: CGFloat) {
        self.init(name: profile.name, color: profile.color, size: size)
    }

    /// Anyone's picture by name and colour (people in a Watch Together room).
    init(name: String, color: String, size: CGFloat) {
        self.name = name
        self.color = color
        self.size = size
    }

    var body: some View {
        let initial = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        Circle()
            .fill(LinearGradient(colors: ArcColor.profile(color), startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initial.isEmpty ? "?" : initial)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

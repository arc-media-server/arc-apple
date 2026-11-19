import ArcKit
import SwiftUI

/// Arc's colours: the web app's dark tokens (web/src/index.css), the same as the Android app's
/// Theme.kt. Arc is dark only, with no brand colour: the logo is white (docs/brand).
enum ArcColor {
    /// A soft dark grey, as the reference design's dark look, rather than near-black.
    static let background = Color(hex: 0x1C1D21)
    /// The page's own blend when a title has no artwork colours, and on pages without artwork:
    /// a slightly cooler top left and warmer bottom right around the background grey.
    static let wash: [Color] = [Color(hex: 0x25282D), Color(hex: 0x222429), Color(hex: 0x1B1B1D), Color(hex: 0x1E1F1E)]
    static let surface = Color(hex: 0x26272D)
    static let surface2 = Color(hex: 0x2F3038)
    static let surface3 = Color(hex: 0x393A43)
    static let foreground = Color(hex: 0xF5F5F7)
    static let muted = Color(hex: 0xA1A1AD)
    static let subtle = Color(hex: 0x6B6B78)
    static let error = Color(hex: 0xFF6B6B)


    /// A profile's colour (web/src/components/Avatar.tsx), as a gradient's two ends.
    static func profile(_ name: String) -> [Color] {
        switch name {
        case "blue": return [Color(hex: 0x38BDF8), Color(hex: 0x2563EB)]
        case "teal": return [Color(hex: 0x5EEAD4), Color(hex: 0x0891B2)]
        case "green": return [Color(hex: 0x34D399), Color(hex: 0x15803D)]
        case "amber": return [Color(hex: 0xFCD34D), Color(hex: 0xCA8A04)]
        case "orange": return [Color(hex: 0xFB923C), Color(hex: 0xDC2626)]
        case "rose": return [Color(hex: 0xF472B6), Color(hex: 0xE11D48)]
        case "slate": return [Color(hex: 0x94A3B8), Color(hex: 0x334155)]
        default: return [Color(hex: 0xA78BFA), Color(hex: 0x4F46E5)]
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A localised string from Localizable.strings, with any arguments filled in.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}

/// The app's log (ArcKit's, under org.arcmediaserver.apple / Arc).
enum ArcLogApp {
    static func info(_ message: String) { ArcLog.shared.info(message) }
    static func warn(_ message: String) { ArcLog.shared.warn(message) }
    static func debug(_ message: String) { ArcLog.shared.debug(message) }
}

/// The page's background: four colours blended corner to corner (top left, top right, bottom
/// left, bottom right). A title's page passes its artwork's colours from the server; without
/// them, or anywhere else, it's Arc's soft grey blend. New colours fade in.
struct PageWash: View {
    var colors: [Color]? = nil

    var body: some View {
        let c = (colors?.count == 4 ? colors : nil) ?? ArcColor.wash
        MeshGradient(width: 2, height: 2,
                     points: [[0, 0], [1, 0], [0, 1], [1, 1]],
                     colors: c)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: c)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.r, green: rgb.g, blue: rgb.b) }
}

// Apple's Liquid Glass (tvOS 26): controls and panels that float over the artwork are glass;
// the artwork and text underneath stay as they are. Older tvOS gets the closest material look.
extension View {
    /// A glass button; `prominent` for the page's main action (Play) and the chosen option: white
    /// with black text, as the sidebar's chosen place (owner, 1 November: no UI colour, only white
    /// and black; the logo is white too).
    @ViewBuilder func arcGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2) // Xcode 26: the tvOS 26 SDK has the glass styles
        if #available(tvOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent).tint(.white).foregroundStyle(.black)
            } else {
                buttonStyle(.glass)
            }
        } else {
            materialButton(prominent: prominent)
        }
        #else
        materialButton(prominent: prominent)
        #endif
    }

    @ViewBuilder private func materialButton(prominent: Bool) -> some View {
        if prominent {
            buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// A floating glass panel (the player's controls, Up Next, the options).
    @ViewBuilder func arcGlassPanel(cornerRadius: CGFloat = 32) -> some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
        #else
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        #endif
    }
    /// A round glass button showing only its icon (its name stays for VoiceOver).
    func roundIconButton() -> some View {
        labelStyle(.iconOnly).arcGlassButton().buttonBorderShape(.circle)
    }
}

/// Liquid Glass in a shape, for custom button styles' backgrounds (the player's round buttons,
/// tabs and tiles, the season tabs); the closest material on older tvOS.
struct GlassFill<S: Shape>: View {
    let shape: S

    var body: some View {
        #if compiler(>=6.2)
        if #available(tvOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }
}

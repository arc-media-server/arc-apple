import ArcKit
import SwiftUI

/// Arc's colours: the web app's dark tokens (web/src/index.css), the same as the Android app's
/// Theme.kt. Arc is dark only. The brand accent is defined here and nowhere else.
enum ArcColor {
    static let background = Color(hex: 0x0B0B10)
    static let surface = Color(hex: 0x15151C)
    static let surface2 = Color(hex: 0x1F1F28)
    static let surface3 = Color(hex: 0x2A2A35)
    static let foreground = Color(hex: 0xF5F5F7)
    static let muted = Color(hex: 0xA1A1AD)
    static let subtle = Color(hex: 0x6B6B78)
    /// Focus, highlights and text on dark.
    static let accent = Color(hex: 0x2BB3A3)
    /// Filled buttons, progress and toggles (with white text).
    static let accentStrong = Color(hex: 0x0B7D72)
    /// The light end of the logo's gradient (#7fdccd → #0b7d72).
    static let accentLight = Color(hex: 0x7FDCCD)
    static let error = Color(hex: 0xFF6B6B)

    static let accentGradient = LinearGradient(colors: [accentLight, accentStrong], startPoint: .topLeading, endPoint: .bottomTrailing)

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

// Apple's Liquid Glass (tvOS 26): controls and panels that float over the artwork are glass;
// the artwork and text underneath stay as they are. Older tvOS gets the closest material look.
extension View {
    /// A glass button; `prominent` for the page's main action (Play), tinted with Arc's accent.
    @ViewBuilder func arcGlassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2) // Xcode 26: the tvOS 26 SDK has the glass styles
        if #available(tvOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent).tint(ArcColor.accentStrong)
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
            buttonStyle(.borderedProminent).tint(ArcColor.accentStrong)
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

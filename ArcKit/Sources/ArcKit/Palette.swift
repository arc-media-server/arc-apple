import Foundation

/// A title's artwork colours from the server (`/items/{id}/artwork/palette`): one colour for each
/// quarter of its backdrop, as they sit in the picture. The title page blends them corner to
/// corner behind everything, so the episodes keep the artwork's colours once it slides away.
public struct ArtworkPalette: Codable, Sendable, Equatable {
    @Default<Defaults.False> public var available: Bool
    public var colors: Corners?

    public init(available: Bool, colors: Corners?) {
        self.available = available
        self.colors = colors
    }

    public struct Corners: Codable, Sendable, Equatable {
        public var topLeft: String
        public var topRight: String
        public var bottomLeft: String
        public var bottomRight: String

        public init(topLeft: String, topRight: String, bottomLeft: String, bottomRight: String) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomLeft = bottomLeft
            self.bottomRight = bottomRight
        }
    }

    /// The four colours toned for a page background (top left, top right, bottom left, bottom
    /// right), or nil when the server has none or one doesn't read.
    public var background: [RGB]? {
        guard available, let c = colors else { return nil }
        let all = [c.topLeft, c.topRight, c.bottomLeft, c.bottomRight].compactMap(RGB.init(hex:))
        return all.count == 4 ? all.map { $0.toned() } : nil
    }
}

/// A colour as red, green and blue from 0 to 1.
public struct RGB: Sendable, Equatable {
    public var r: Double, g: Double, b: Double

    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    /// "#rrggbb" (the leading # optional).
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        r = Double((value >> 16) & 0xFF) / 255
        g = Double((value >> 8) & 0xFF) / 255
        b = Double(value & 0xFF) / 255
    }

    /// Calmer and darker, so white text stays readable on it: the hue is kept, the saturation
    /// is at most 0.55 and the brightness sits between 0.12 and 0.30.
    public func toned() -> RGB {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        let saturation = maxC == 0 ? 0 : min(delta / maxC * 0.8, 0.55)
        let brightness = min(max(maxC * 0.6, 0.12), 0.30)
        return RGB(hue: hue, saturation: saturation, brightness: brightness)
    }

    init(hue: Double, saturation s: Double, brightness v: Double) {
        let h = hue * 6
        let i = Int(h) % 6
        let f = h - Double(Int(h))
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: (r, g, b) = (v, t, p)
        case 1: (r, g, b) = (q, v, p)
        case 2: (r, g, b) = (p, v, t)
        case 3: (r, g, b) = (p, q, v)
        case 4: (r, g, b) = (t, p, v)
        default: (r, g, b) = (v, p, q)
        }
    }
}

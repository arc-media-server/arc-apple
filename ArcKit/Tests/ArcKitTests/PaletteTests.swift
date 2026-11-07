import XCTest
@testable import ArcKit

final class PaletteTests: XCTestCase {
    func testTheServersCornersBecomeADarkCalmBackground() throws {
        let json = ##"{"available":true,"algorithm":"regional-v1","colors":{"top_left":"#ff0000","top_right":"#2040c0","bottom_left":"#ffffff","bottom_right":"#000000"}}"##
        let palette = try ArcJSON.decoder.decode(ArtworkPalette.self, from: Data(json.utf8))
        let bg = try XCTUnwrap(palette.background)
        XCTAssertEqual(bg.count, 4)
        for c in bg {
            XCTAssertLessThanOrEqual(max(c.r, c.g, c.b), 0.30 + 1e-9)
            XCTAssertGreaterThanOrEqual(max(c.r, c.g, c.b), 0.12 - 1e-9)
        }
        // Red stays red, only darker and calmer.
        XCTAssertGreaterThan(bg[0].r, bg[0].g)
        XCTAssertEqual(bg[0].g, bg[0].b, accuracy: 1e-9)
        // Blue stays blue.
        XCTAssertGreaterThan(bg[1].b, bg[1].r)
        // White and black become greys.
        XCTAssertEqual(bg[2].r, bg[2].b, accuracy: 1e-9)
        XCTAssertEqual(bg[3].r, 0.12, accuracy: 1e-9)
    }

    func testNoPaletteWhenTheServerHasNone() throws {
        let none = try ArcJSON.decoder.decode(ArtworkPalette.self, from: Data(##"{"available":false,"reason":"no artwork"}"##.utf8))
        XCTAssertNil(none.background)
        let bad = ArtworkPalette(available: true, colors: .init(topLeft: "#zzz", topRight: "#000000", bottomLeft: "#000000", bottomRight: "#000000"))
        XCTAssertNil(bad.background)
    }
}

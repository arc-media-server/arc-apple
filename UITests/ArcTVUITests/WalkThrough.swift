import XCTest

/// Walks the app in the tvOS simulator against the stand-in Arc (UITests/StandIn/serve.py) and
/// keeps a screenshot of each screen, so changes can be looked at without an Apple TV. The
/// workflow exports the screenshots from the test results. Nothing here checks playback on a
/// real Apple TV.
@MainActor
final class WalkThrough: XCTestCase {
    private var remote: XCUIRemote { XCUIRemote.shared }
    private var server: String { ProcessInfo.processInfo.environment["ARC_STANDIN_URL"] ?? "http://127.0.0.1:8080" }

    func testWalkThrough() {
        continueAfterFailure = true
        // A first launch with no server saved: the address screen.
        let app = XCUIApplication()
        app.launchArguments = ["-server", ""]
        app.launch()
        pause(3)
        shot("01-server")

        // The stand-in's address, as if typed: the sign-in code, approved on the third check.
        app.terminate()
        app.launchArguments = ["-server", server]
        app.launch()
        pause(3)
        shot("02-sign-in-code")
        pause(9)
        shot("03-profiles")

        // The first profile (no PIN), then Home with its pictures loaded.
        remote.press(.select)
        pause(6)
        shot("04-home")
        // Up reaches the hero's Play, Watchlist and Info; down returns to the first row.
        press(.up)
        pause(1)
        shot("04b-home-hero-buttons")
        press(.down)
        pause(1)
        press(.right)
        pause(3)
        shot("05-home-focus-moved")
        press(.down)
        pause(3)
        shot("06-home-second-row")

        // The focused title's page, then play it.
        remote.press(.select)
        pause(4)
        shot("07-title-page")
        press(.down, 2)
        pause(2)
        shot("08-title-page-scrolled")
        // Up returns to the button row under the focus (the middle of Play, Watched and
        // Watchlist), so left to Play.
        press(.up, 4)
        press(.left, 3)
        remote.press(.select)
        pause(6)
        shot("09-player")
        remote.press(.playPause)
        pause(2)
        shot("10-player-paused")
        // Skip Intro has the focus (the stand-in marks the clip's start as an intro); then
        // down opens Subtitles and Audio, and the stand-in's track turns on.
        remote.press(.select)
        pause(2)
        press(.down)
        pause(2)
        shot("10b-player-options")
        press(.down)
        remote.press(.select)
        pause(3)
        shot("10c-player-subtitles")
        remote.press(.menu)
        pause(1)
        // Back closes the player, Back again leaves the title page for Home. (A third would
        // leave the app: Back on Home goes to the Apple TV's home screen, as tvOS apps do.)
        remote.press(.menu)
        pause(1)
        remote.press(.menu)
        pause(3)
        shot("11-back-from-player")

        // A show: down the rows until a show's page has seasons.
        press(.down)
        pause(2)
        shot("12-home-third-row")
        remote.press(.select)
        pause(4)
        shot("13-third-row-title")
        press(.down, 6)
        pause(3)
        shot("14-title-page-rows")

        // Back to Home, then Back again opens the sidebar, and down it: the Watchlist, each
        // library, Playlists and Settings (the place under the focus opens as the focus moves).
        remote.press(.menu)
        pause(2)
        remote.press(.menu)
        pause(2)
        shot("15-tabs")
        for i in 1...7 {
            press(.down)
            pause(3)
            shot(String(format: "16-tab-%02d", i))
        }

        // A library: its sort and filters, then the grid, and holding Select on a title.
        press(.up, 3)
        pause(3)
        press(.right)
        pause(1)
        shot("17-library-header")
        press(.down)
        pause(2)
        shot("18-library-grid")
        remote.press(.select, forDuration: 1.6)
        pause(2)
        shot("19-title-actions")
        remote.press(.menu)
        pause(1)

        // Search: type a few letters; results follow the typing.
        remote.press(.menu)
        pause(1)
        press(.up, 10)
        pause(2)
        shot("20-search")
        press(.right)
        pause(1)
        // Select on the keyboard's first key types "a" (the stand-in has answers for "a", "al"…
        // "alien" and "f"… "firefly"); typing into the field directly is used when it's exposed.
        let field = app.searchFields.firstMatch
        if field.exists {
            field.typeText("alien")
        } else {
            remote.press(.select)
        }
        pause(4)
        shot("21-search-results")
    }

    private func press(_ button: XCUIRemote.Button, _ times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            Thread.sleep(forTimeInterval: 0.4)
        }
    }

    private func pause(_ seconds: Double) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}

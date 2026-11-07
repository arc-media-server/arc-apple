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
        // With rooms on the stand-in, Home opens on its Watch Together row: down to the titles.
        if app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Watch Together:'")).firstMatch.hasFocus {
            press(.down)
            pause(2)
        }
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
        // The foot of the page: Cast, then the About, Details, Crew and Playback cards.
        press(.down, 3)
        pause(2)
        shot("08b-title-page-cards")
        // Up returns to the button row under the focus, then left to Play (one more left would
        // open the sidebar).
        press(.up, 8)
        let play = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Play' OR label BEGINSWITH 'Resume'")).firstMatch
        for _ in 0..<4 where !play.hasFocus {
            press(.left)
        }
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
        // Right moves 10 seconds on, with the timeline thumbnail (the stand-in has a sheet).
        press(.right)
        pause(1)
        shot("10a-player-thumbnail")
        press(.down)
        pause(2)
        shot("10b-player-options")
        press(.down)
        remote.press(.select)
        pause(3)
        shot("10c-player-subtitles")
        // Further down the panel: Quality, Version and Chapters.
        press(.down, 4)
        pause(1)
        shot("10d-player-quality")
        remote.press(.menu)
        pause(1)
        // Back closes the player, Back again leaves the title page for Home. (A third would
        // leave the app: Back on Home goes to the Apple TV's home screen, as tvOS apps do.)
        remote.press(.menu)
        pause(1)
        remote.press(.menu)
        pause(3)
        shot("11-back-from-player")

        // A show: down the rows until a show's card (Recently Added in TV) has the focus.
        let shows = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Mushoku' OR label BEGINSWITH 'Firefly'"))
        for _ in 0..<6 {
            press(.down)
            pause(1.5)
            if shows.allElementsBoundByIndex.contains(where: { $0.hasFocus }) { break }
        }
        shot("12-home-third-row")
        remote.press(.select)
        pause(4)
        shot("13-third-row-title")
        // Down from Play: the episode browser comes up (the logo small at the top, the season
        // tabs, the episodes); along it, the focused episode shows its overview; along the
        // tabs, the episodes follow.
        press(.down)
        pause(2)
        shot("13a-episodes")
        press(.right)
        pause(1)
        shot("13b-episode-focused")
        press(.up)
        press(.right)
        pause(2)
        shot("13c-next-season")
        press(.down, 6)
        pause(3)
        shot("14-title-page-rows")

        // Back to Home, and Back again opens the sidebar (its icons stay where they are; the glass
        // and the names fade in), then down it: the Watchlist, each library, Playlists and Settings.
        remote.press(.menu)
        pause(2)
        remote.press(.menu)
        pause(2)
        shot("15-tabs")
        for i in 1...7 { // the last press finds the end of the sidebar and stays
            press(.down)
            pause(3)
            shot(String(format: "16-tab-%02d", i))
        }

        // A library opens on Recommended: a hero and rows, the pill bar above. Then up to the pill
        // bar and Browse: sort and filters, the grid, and holding Select on a title.
        // (The sidebar only highlights as the focus moves; Select opens the place and shuts it.)
        press(.up, 3)
        pause(1)
        remote.press(.select)
        pause(4)
        shot("17-library-recommended")
        press(.down)
        pause(2)
        shot("17a-library-recommended-rows")
        // Up from the rows reaches the pill bar (it floats over the hero), then right to Browse.
        let browse = app.buttons["Browse"]
        for _ in 0..<5 where !app.buttons["Recommended"].hasFocus && !browse.hasFocus && !app.buttons["Collections"].hasFocus {
            press(.up)
        }
        // Whichever pill Up lands on: right to the last (Collections), then one back.
        if !browse.hasFocus {
            press(.right, 3)
            press(.left)
        }
        pause(1)
        shot("17b-library-pills")
        remote.press(.select)
        pause(3)
        shot("17-library-header")
        press(.down)
        pause(2)
        shot("18-library-grid")
        remote.press(.select, forDuration: 1.6)
        pause(2)
        shot("19-title-actions")
        remote.press(.menu)
        pause(1)

        // Search, at the top of the sidebar (Back from the library opens it): type a few letters;
        // results follow the typing.
        remote.press(.menu)
        pause(1)
        press(.up, 10) // to the profile at the top, then down one to Search
        press(.down)
        remote.press(.select)
        pause(2)
        shot("20-search")
        // Select on the keyboard's first key types "a" (the stand-in has answers for "a", "al"…
        // "alien" and "f"… "firefly"); typing into the field directly is used when it's exposed.
        let field = app.searchFields.firstMatch
        if field.exists && field.hasFocus {
            field.typeText("alien")
        } else {
            remote.press(.select)
        }
        pause(4)
        shot("21-search-results")

        // Watch Together (the stand-in has a room this profile hosts and one Jo invited it to):
        // back to Home, up to the Watch Together row, the host's lobby, then the guest's.
        // Back once from Search's first page opens the sidebar on Search (a second Back would
        // leave the app); Home is the next place down.
        remote.press(.menu)
        pause(1)
        let home = app.buttons["Home"]
        for _ in 0..<4 where !home.hasFocus { press(.down) }
        remote.press(.select)
        pause(2)
        // Home still has the title opened earlier, and the sidebar steps aside on opened pages:
        // Back closes them until Home's first page (where the sidebar's buttons work again).
        for _ in 0..<4 where !home.isEnabled {
            remote.press(.menu)
            pause(1.5)
        }
        // Home keeps its place from earlier steps; choosing it again (Left reopens the sidebar on
        // it) starts it afresh at the top, on the Watch Together row.
        press(.left)
        for _ in 0..<4 where !home.hasFocus { press(.down) }
        remote.press(.select)
        pause(5)
        // Choosing Home again starts it afresh at the top, on the Watch Together row (from the
        // sidebar's landing stop, Down goes on into the page if the row hasn't the focus yet).
        let room = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Watch Together'")).firstMatch
        if !(room.exists && room.hasFocus) { press(.down) }
        shot("22-home-watch-together")
        remote.press(.select)
        pause(5)
        shot("23-lobby-host")
        // Back closes the player, which leaves the room; then the next room, as a guest.
        remote.press(.menu)
        pause(3)
        press(.right)
        remote.press(.select)
        pause(5)
        shot("24-lobby-guest")
        remote.press(.menu)
        pause(3)

        // Inviting: hold Select on a title, Watch Together…, and choose someone.
        press(.down)
        pause(2)
        remote.press(.select, forDuration: 1.6)
        pause(2)
        let together = app.descendants(matching: .any)["Watch Together…"].firstMatch
        for _ in 0..<6 where !together.hasFocus { press(.down) }
        remote.press(.select)
        pause(3)
        shot("25-invite-panel")
        remote.press(.select)
        pause(1)
        shot("26-invite-chosen")
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

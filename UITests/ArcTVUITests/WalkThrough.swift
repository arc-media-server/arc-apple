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
        // Home opens on its first row of titles; Watch Together's row sits under Continue Watching.
        press(.right)
        pause(3)
        shot("05-home-focus-moved")
        press(.down)
        pause(2)
        // Past Watch Together's row (the stand-in has rooms) to the second row of titles.
        let inRooms = app.buttons.matching(NSPredicate(format: "(label BEGINSWITH 'Watch Together' OR label == 'Join with a Code') AND hasFocus == true")).firstMatch
        if inRooms.exists {
            press(.down)
            pause(2)
        }
        pause(1)
        shot("06-home-second-row")

        // The focused title's page, then play it.
        remote.press(.select)
        pause(4)
        shot("07-title-page")
        // One Down: the cast comes up under the hero's buttons, which stay in view.
        press(.down)
        pause(2)
        shot("08-title-page-scrolled")
        // The first person in the cast: their page, then back.
        remote.press(.select)
        pause(4)
        shot("08a-person")
        press(.right)
        pause(2)
        shot("08a-person-focus-moved")
        remote.press(.menu)
        pause(2)
        // The foot of the page: Cast, then the About, Details, Crew and Playback cards.
        press(.down, 4)
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
        // Skip Intro has the focus (the stand-in marks the clip's start as an intro).
        remote.press(.select)
        pause(2)
        // Right moves 10 seconds on, with the timeline thumbnail (the stand-in has a sheet).
        press(.right)
        pause(1)
        shot("10a-player-thumbnail")
        // Down opens the Info card under the tab row; Back returns to the picture.
        press(.down)
        pause(2)
        shot("10b-player-info")
        remote.press(.menu)
        pause(1)
        // Up goes to the round buttons; Select opens Subtitles (tvOS's own menu), Down and Select
        // turn the stand-in's track on, and the menu closes back to its button.
        press(.up)
        pause(1)
        remote.press(.select)
        pause(2)
        shot("10c-player-subtitles-menu")
        press(.down)
        remote.press(.select)
        pause(3)
        shot("10c-player-subtitles")
        // Along to Playback (the first): Zoom Mode, Playback Speed, Quality, Version.
        press(.left, 2)
        remote.press(.select)
        pause(1)
        shot("10d-player-playback")
        // Then the Cast card: Back closes the menu, Back leaves the controls, Down opens Info, and
        // along the tabs to Cast.
        remote.press(.menu)
        pause(1)
        remote.press(.menu)
        pause(1)
        press(.down)
        pause(1)
        let castTab = app.buttons["Cast"]
        for _ in 0..<4 where !castTab.hasFocus { press(.right) }
        pause(2)
        shot("10e-player-cast")
        // Back leaves the controls, Back closes the (paused) player, and Back leaves the title
        // page for Home. (One more would open the sidebar.)
        remote.press(.menu)
        pause(1)
        remote.press(.menu)
        pause(1)
        remote.press(.menu)
        pause(3)
        shot("11-back-from-player")

        // Vertical moves preserve the previous card's column. The TV row can be entered
        // on either side of Breaking Bad, so move towards it before selecting.
        let tvRow = app.staticTexts["Recently Added in TV Shows"]
        let tvTitles = ["The Office", "Breaking Bad", "The Last of Us", "Stranger Things", "Severance"]
        let shows = app.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [tvTitles]))
        func focusedShow() -> XCUIElement? {
            guard tvRow.exists, tvRow.frame.intersects(app.frame) else { return nil }
            return shows.allElementsBoundByIndex.first { $0.hasFocus && $0.frame.minY >= tvRow.frame.maxY }
        }
        for _ in 0..<6 where focusedShow() == nil { press(.down) }
        for _ in tvTitles {
            guard let focused = focusedShow(), let column = tvTitles.firstIndex(of: focused.label) else { break }
            if focused.label == "Breaking Bad" { break }
            press(column == 0 ? .right : .left)
        }
        guard focusedShow()?.label == "Breaking Bad" else {
            XCTFail("Expected Breaking Bad to have focus in Recently Added in TV Shows")
            return
        }
        shot("12-home-third-row")
        remote.press(.select)
        pause(4)
        shot("13-third-row-title")
        // Down from Play: the episode browser comes up on the episode to watch next (the logo
        // small at the top, the season tabs, the episodes); along it, the focused episode shows
        // its overview; Up is the season tabs, and along them the episodes follow.
        press(.down)
        pause(2)
        shot("13a-episodes")
        press(.right)
        pause(1)
        shot("13b-episode-focused")
        press(.up)
        pause(1)
        shot("13c-season-tabs")
        // Left along the season tabs (the shared library's shows have one season, so it may stay).
        press(.left)
        pause(2)
        shot("13d-next-season")
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

        // Settings (the last place), then About inside it; Back twice returns to the sidebar.
        remote.press(.select)
        pause(3)
        press(.right)
        let automaticLabel = app.staticTexts["Sign in automatically"]
        for _ in 0..<10 where !automaticLabel.isHittable { press(.down) }
        shot("16a-automatic-sign-in")
        let sendLogs = app.buttons["send-device-logs"]
        for _ in 0..<12 where !sendLogs.hasFocus { press(.down) }
        XCTAssertTrue(sendLogs.hasFocus)
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Logs sent."].waitForExistence(timeout: 10))
        shot("16c-send-logs")
        let about = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'About'")).firstMatch
        for _ in 0..<12 where !about.hasFocus { press(.down) }
        remote.press(.select)
        pause(3)
        shot("16b-about")
        remote.press(.menu)
        pause(1)
        remote.press(.menu)
        pause(2)

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
        // The library's Collections, laid out as its grid, and inside one: then back.
        let collectionsPill = app.buttons["Collections"]
        for _ in 0..<6 where !collectionsPill.hasFocus && !browse.hasFocus { press(.up) }
        for _ in 0..<3 where !collectionsPill.hasFocus { press(.right) }
        remote.press(.select)
        pause(3)
        shot("19a-library-collections")
        press(.down)
        remote.press(.select)
        pause(4)
        shot("19b-collection")
        remote.press(.menu)
        pause(2)

        // Open the named sidebar destination, then transfer focus from its invisible
        // landing stop to the native Search keyboard before entering a query.
        remote.press(.menu)
        pause(1)
        let searchPlace = app.buttons["Search"]
        for _ in 0..<10 where !searchPlace.hasFocus { press(.up) }
        guard searchPlace.hasFocus else {
            XCTFail("Expected Search to have focus in the sidebar")
            return
        }
        remote.press(.select)
        pause(2)
        shot("20-search")

        press(.down)
        let field = app.searchFields.firstMatch
        if field.exists && field.hasFocus {
            field.typeText("dune")
        } else {
            let letter = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", "d"))
            func letterHasFocus() -> Bool { letter.allElementsBoundByIndex.contains { $0.hasFocus } }
            for _ in 0..<8 where !letterHasFocus() { press(.right) }
            guard letterHasFocus() else {
                XCTFail("Expected to focus the D key on the Search keyboard")
                return
            }
            remote.press(.select)
        }
        guard app.buttons["Dune"].waitForExistence(timeout: 10) else {
            XCTFail("Expected Search to return the recorded Dune result")
            return
        }
        shot("21-search-results")

        // Watch Together (the stand-in has a room this profile hosts and one Jo invited it to):
        // back to Home, up to the Watch Together row, the host's lobby, then the guest's.
        // Search has the whole screen; Left from the keyboard's first key opens the sidebar on
        // Search (Back belongs to the keyboard there). Home is the next place down.
        let home = app.buttons["Home"]
        for _ in 0..<30 where !(searchPlace.hasFocus || home.hasFocus) { remote.press(.left) }
        pause(1)
        for _ in 0..<4 where !home.hasFocus { press(.down) }
        remote.press(.select)
        pause(2)
        // Home still has the title opened earlier, and the sidebar steps aside on opened pages:
        // Back closes them until Home's first page (where the sidebar's buttons work again).
        for _ in 0..<4 where !home.isEnabled {
            remote.press(.menu)
            pause(1.5)
        }
        // Home keeps its place from earlier steps: up its rows to Watch Together's, under
        // Continue Watching (down again if the focus was already above it).
        let room = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Watch Together'")).firstMatch
        if !(room.exists && room.hasFocus) { press(.right) }
        for _ in 0..<10 where !(room.exists && room.hasFocus) { press(.up) }
        for _ in 0..<3 where !(room.exists && room.hasFocus) { press(.down) }
        pause(2)
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

        // Home without Watch Together rooms, as most people see it (the README's picture): the
        // stand-in drops its rooms, then a fresh start, the first profile, and Home on Continue
        // Watching.
        var request = URLRequest(url: URL(string: server + "/api/v1/standin/no-rooms")!)
        request.httpMethod = "POST"
        let done = expectation(description: "rooms dropped")
        URLSession.shared.dataTask(with: request) { _, _, _ in done.fulfill() }.resume()
        wait(for: [done], timeout: 10)
        app.terminate()
        app.launch()
        pause(4)
        remote.press(.select)
        pause(8)
        shot("27-home-continue-watching")
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

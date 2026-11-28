import XCTest

/// Walks the iPhone app in the simulator against the stand-in Arc (UITests/StandIn/serve.py) and
/// keeps a screenshot of each screen, so changes can be looked at without an iPhone. The workflow
/// exports the screenshots from the test results. Nothing here checks playback on a real device.
@MainActor
final class MobileWalkThrough: XCTestCase {
    private var server: String { ProcessInfo.processInfo.environment["ARC_STANDIN_URL"] ?? "http://127.0.0.1:8080" }

    func testWalkThrough() {
        continueAfterFailure = true
        XCUIDevice.shared.orientation = .portrait
        // A first launch with no server saved: the address screen.
        let app = XCUIApplication()
        app.launchArguments = ["-server", ""]
        app.launch()
        pause(3)
        shot("m01-server")

        // The stand-in's address, as if typed: the sign-in code, approved on the third check.
        app.terminate()
        app.launchArguments = ["-server", server]
        app.launch()
        pause(3)
        shot("m02-sign-in-code")
        pause(9)
        shot("m03-profiles")

        // The first profile (no PIN), then Home with its pictures loaded.
        tap(app.buttons["Jordan"])
        pause(6)
        shot("m04-home")
        app.swipeUp()
        pause(2)
        shot("m05-home-scrolled")
        app.swipeDown()
        app.swipeDown()
        pause(1)

        // A title's actions, from touching and holding its card.
        let card = app.scrollViews.buttons.element(boundBy: 0)
        if card.waitForExistence(timeout: 3) {
            card.press(forDuration: 1.2)
            pause(2)
            shot("m06-card-menu")
            app.tap()
            pause(1)
        }

        // A show's page from the Watchlist row: its seasons and episodes, then its cast.
        let show = app.buttons["The Last of Us"].firstMatch
        if show.waitForExistence(timeout: 4) {
            show.tap()
            pause(4)
            shot("m07-show-page")
            app.swipeUp()
            pause(2)
            shot("m08-show-episodes")
            app.swipeUp()
            pause(2)
            shot("m09-show-foot")
            back(app)
        }

        // A film's page, then play it: the player turns the iPhone sideways. The stand-in's clip is
        // short, so the player may close by itself at its end.
        let film = app.buttons["Interstellar"].firstMatch
        if film.waitForExistence(timeout: 4) {
            film.tap()
            pause(4)
            shot("m10-film-page")
            let play = app.buttons["details.play"]
            if play.waitForExistence(timeout: 3) {
                play.tap()
                pause(3)
                shot("m11-player")
                app.tap()
                pause(1)
                shot("m11a-player-controls")
                let close = app.buttons["player.close"]
                if close.exists && !close.isHittable { app.tap(); pause(1) }
                if close.exists && close.isHittable { close.tap() }
                pause(3)
                XCUIDevice.shared.orientation = .portrait
                pause(1)
            }
            back(app)
        }

        // Libraries, then the first library's grid and its Sort menu.
        tap(app.tabBars.buttons.element(boundBy: 1))
        pause(3)
        shot("m12-libraries")
        let firstLibrary = app.collectionViews.cells.element(boundBy: 0)
        if firstLibrary.waitForExistence(timeout: 3) {
            tap(firstLibrary)
            pause(4)
            shot("m13-library")
            let sort = app.buttons["library.sort"]
            if sort.exists {
                tap(sort)
                pause(1)
                shot("m14-library-sort")
                app.tap()
                pause(1)
            }
        }

        // Search.
        tap(app.tabBars.buttons.element(boundBy: 2))
        pause(2)
        let field = app.searchFields.firstMatch
        if field.waitForExistence(timeout: 3) {
            field.tap()
            field.typeText("the")
            pause(4)
            shot("m15-search")
        }

        // Settings, from the profile picture in the bar.
        tap(app.tabBars.buttons.element(boundBy: 0))
        pause(2)
        let settings = app.buttons["settings.open"]
        if settings.waitForExistence(timeout: 3) {
            tap(settings)
            pause(3)
            shot("m16-settings")
            tap(app.buttons["settings.done"])
            pause(1)
        }

        // iPad-sized layout isn't walked here; the same screens follow the size class.
        XCUIDevice.shared.orientation = .landscapeLeft
        pause(2)
        shot("m17-home-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    /// The bar's back button, as a swipe from the edge would.
    private func back(_ app: XCUIApplication) {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.exists && button.isHittable { button.tap() }
        pause(2)
    }

    private func tap(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 4) { element.tap() }
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

import XCTest

final class WaveCatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFullGameProof() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seed", "7"]
        app.launch()

        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        save("01-menu")
        play.tap()

        let score = app.staticTexts["score"]
        XCTAssertTrue(score.waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["safeLane"].waitForExistence(timeout: 4))

        var sawMidgame = false
        var sawCatch = false
        var sawJelly = false
        var previous = 0
        let catchDeadline = Date().addingTimeInterval(22)
        while Date() < catchDeadline {
            if app.buttons["playAgainButton"].exists { break }
            let jelly = app.staticTexts["jellyfishOnScreen"]
            if jelly.exists && jelly.label == "1" && !sawJelly {
                save("04-jellyfish")
                sawJelly = true
            }
            let now = number(in: score)
            if now > 0 && !sawMidgame {
                save("02-midgame")
                sawMidgame = true
            }
            if now > previous && now >= 2 && !sawCatch {
                save("03-catch")
                sawCatch = true
            }
            previous = now
            if now >= 3 && sawMidgame && sawCatch && sawJelly { break }
            tapLane(app, name: app.staticTexts["safeLane"].label, fallback: "lowerLeft")
        }

        XCTAssertGreaterThan(number(in: app.staticTexts["score"]), 0, "score never left zero")
        if !sawMidgame { save("02-midgame") }
        if !sawCatch { save("03-catch") }
        if !sawJelly {
            let jelly = app.staticTexts["jellyfishOnScreen"]
            if jelly.label == "1" {
                save("04-jellyfish")
                sawJelly = true
            }
        }

        let deathDeadline = Date().addingTimeInterval(28)
        while Date() < deathDeadline && !app.buttons["playAgainButton"].exists {
            let lane = app.staticTexts["safeLane"].label
            tapLane(app, name: opposite(lane), fallback: "upperRight")
        }

        let again = app.buttons["playAgainButton"]
        XCTAssertTrue(again.waitForExistence(timeout: 8), "game over did not appear")
        save("05-gameover")
        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: again)
        waitForExpectations(timeout: 4)
        again.tap()

        let backToZero = NSPredicate(format: "label == '0'")
        expectation(for: backToZero, evaluatedWith: app.staticTexts["score"])
        waitForExpectations(timeout: 6)
        XCTAssertFalse(app.buttons["playAgainButton"].exists)
        save("06-restart")
        XCTAssertTrue(sawJelly, "a jellyfish should appear in the proof run")
    }

    private func tapLane(_ app: XCUIApplication, name: String, fallback: String) {
        let lane = name.isEmpty || name == "none" ? fallback : name
        let other = app.otherElements["zone.\(lane)"]
        let button = app.buttons["zone.\(lane)"]
        let zone = other.exists ? other : button
        if zone.exists {
            zone.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func opposite(_ lane: String) -> String {
        switch lane {
        case "upperLeft": return "lowerRight"
        case "upperRight": return "lowerLeft"
        case "lowerLeft": return "upperRight"
        case "lowerRight": return "upperLeft"
        default: return "upperRight"
        }
    }

    private func number(in element: XCUIElement) -> Int {
        Int(element.label.filter(\.isNumber)) ?? 0
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: "/tmp/wavecatch-proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
    }
}

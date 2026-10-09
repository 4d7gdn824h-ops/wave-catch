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
        XCTAssertFalse(app.buttons["debugGear"].exists)
        save("01-menu")
        mark("record-start")
        Thread.sleep(forTimeInterval: 1.5)
        let started = Date()
        play.tap()

        let score = app.staticTexts["score"]
        XCTAssertTrue(score.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["debugGear"].exists)

        var sawRing = false
        var sawMidgame = false
        var sawCatch = false
        var sawJelly = false
        var previous = 0
        let watchUntil = Date().addingTimeInterval(12)
        while Date() < watchUntil && !(sawRing && sawJelly && sawMidgame && sawCatch) {
            if !sawRing && app.staticTexts["ringLit"].label == "1" {
                save("07-landing-ring")
                sawRing = true
            }
            if !sawJelly && app.staticTexts["jellyfishOnScreen"].label == "1" {
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
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertTrue(sawRing, "landing ring did not light")
        XCTAssertTrue(sawJelly, "a jellyfish should appear in the proof run")
        XCTAssertTrue(sawMidgame, "score never left zero")
        XCTAssertTrue(sawCatch, "a second catch was not shown")

        let elapsed = Date().timeIntervalSince(started)
        Thread.sleep(forTimeInterval: max(0, 32 - elapsed))

        let again = app.buttons["playAgainButton"]
        let overDeadline = Date().addingTimeInterval(14)
        while Date() < overDeadline && !again.exists {
            Thread.sleep(forTimeInterval: 0.4)
        }
        XCTAssertTrue(again.waitForExistence(timeout: 2), "game over did not appear")
        XCTAssertGreaterThanOrEqual(number(in: app.staticTexts["score"]), 8, "score stayed under 8")
        XCTAssertGreaterThanOrEqual(number(in: app.staticTexts["longestCombo"]), 10, "combo never reached 10")

        let newBest = app.staticTexts["newBest"]
        XCTAssertTrue(newBest.waitForExistence(timeout: 4), "NEW BEST was not on the game over card")
        Thread.sleep(forTimeInterval: 1.25)
        _ = XCUIScreen.main.screenshot()
        Thread.sleep(forTimeInterval: 0.4)
        save("05-gameover")
        XCTAssertTrue(newBest.exists)
        XCTAssertEqual(newBest.label, "NEW BEST")

        let enabled = NSPredicate(format: "isEnabled == true")
        expectation(for: enabled, evaluatedWith: again)
        waitForExpectations(timeout: 4)
        again.tap()

        let backToZero = NSPredicate(format: "label == '0'")
        expectation(for: backToZero, evaluatedWith: app.staticTexts["score"])
        waitForExpectations(timeout: 6)
        XCTAssertFalse(app.buttons["playAgainButton"].exists)
        save("06-restart")
        Thread.sleep(forTimeInterval: 2.6)
        mark("record-stop")
        Thread.sleep(forTimeInterval: 1.5)
    }

    private func number(in element: XCUIElement) -> Int {
        Int(element.label.filter(\.isNumber)) ?? 0
    }

    private func mark(_ name: String) {
        let directory = URL(fileURLWithPath: "/tmp/wavecatch-proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("1".utf8))
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

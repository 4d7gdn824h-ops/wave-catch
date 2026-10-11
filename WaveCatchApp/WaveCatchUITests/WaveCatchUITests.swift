import UIKit
import XCTest

final class WaveCatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testFullGameProof() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seed", "7", "-WCSpotlight", "-WCProofMode"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["debugGear"].exists)
        save("01-menu")
        // The recorder starts on this marker, then writes recording-live only after
        // simctl prints "Recording started". Stay on the menu until that happens.
        mark("menu-ready")
        XCTAssertTrue(waitForMarker("recording-live", timeout: 70), "recording did not start")
        let started = Date()
        play.tap()

        let score = app.descendants(matching: .any)["score"]
        XCTAssertTrue(score.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["debugGear"].exists)

        let again = app.buttons["playAgainButton"]
        var sawMiss = false
        var sawRing = false
        var sawMidgame = false
        var sawCatch = false
        var sawGolden = false
        var previous = 0

        func sample() {
            let over = again.exists
            if over {
                sawMiss = true
            } else if let lives = probe(app, "lives"), let count = Int(lives.filter(\.isNumber)), count < 3 {
                sawMiss = true
            }
            let now = number(in: score)
            // Pool and catch shots have to be the live pool, not the game-over card.
            // 03 is the first score increase we actually see, so it lands on a catch.
            guard !over else { return }
            if now > 0 && !sawMidgame {
                save("02-pool")
                sawMidgame = true
            } else if sawMidgame && !sawCatch && now > previous {
                save("03-catch")
                sawCatch = true
            }
            previous = now
        }

        for side in ["north", "east", "south", "west"] {
            sample()
            let id = "edge.\(side)"
            let any = app.descendants(matching: .any)[id]
            XCTAssertTrue(any.waitForExistence(timeout: 4), "missing \(id)")
        }
        sample()

        let watchUntil = Date().addingTimeInterval(40)
        while Date() < watchUntil && !(sawRing && sawGolden && sawMidgame && sawCatch) {
            sample()
            if !sawRing && probe(app, "ringLit") == "1" {
                save("07-swell-ring")
                sawRing = true
            }
            if !sawGolden && probe(app, "sawGolden") == "1" {
                Thread.sleep(forTimeInterval: 0.35)
                save("04-golden")
                sawGolden = true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertTrue(sawRing, "the swell ring did not light")
        XCTAssertTrue(sawGolden, "a golden wave should appear in the proof run")
        XCTAssertTrue(sawMidgame, "score never left zero")
        XCTAssertTrue(sawCatch, "a second catch was not shown")

        let niceDeadline = started.addingTimeInterval(50)
        var sawNiceText = false
        while Date() < niceDeadline && !sawNiceText {
            sample()
            if probe(app, "sawNice") == "1" {
                sawNiceText = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(sawNiceText, "Nice! was not reached")
        let pitchDeadline = Date().addingTimeInterval(2)
        while Date() < pitchDeadline && (probe(app, "maxPitch").flatMap { Int($0.filter(\.isNumber)) } ?? 0) < 3 {
            sample()
            Thread.sleep(forTimeInterval: 0.1)
        }
        sample()
        XCTAssertGreaterThanOrEqual(probe(app, "maxPitch").flatMap { Int($0.filter(\.isNumber)) } ?? 0, 3, "the pitch ladder did not rise")
        XCTAssertEqual(probe(app, "sawGolden"), "1", "a golden wave was not seen")
        XCTAssertEqual(probe(app, "sawBigWave"), "1", "SURGE did not start")
        XCTAssertTrue(sawRing && sawGolden && sawMidgame && sawCatch, "play screenshots were not all saved")

        // Armor held the lives through the shots. Turn it off and miss on purpose.
        let armor = app.buttons["proofArmor"]
        XCTAssertTrue(armor.waitForExistence(timeout: 2), "proof armor toggle was not available")
        armor.tap()

        let overDeadline = Date().addingTimeInterval(70)
        while Date() < overDeadline && !again.exists {
            sample()
            Thread.sleep(forTimeInterval: 0.2)
        }
        sample()
        XCTAssertTrue(sawMiss, "the proof never missed")
        XCTAssertTrue(again.waitForExistence(timeout: 2), "game over did not appear")
        let newBest = app.descendants(matching: .any)["newBest"]
        XCTAssertTrue(newBest.waitForExistence(timeout: 1), "NEW BEST was not on the game over card")
        expectation(for: NSPredicate(format: "label == 'NEW BEST'"), evaluatedWith: newBest)
        waitForExpectations(timeout: 1)
        XCTAssertGreaterThanOrEqual(number(in: app.descendants(matching: .any)["longestCombo"]), 5, "combo never reached Nice")
        save("05-gameover")
        again.tap()

        let backToZero = NSPredicate(format: "label == '0'")
        expectation(for: backToZero, evaluatedWith: score)
        waitForExpectations(timeout: 0.7)
        XCTAssertFalse(app.buttons["playAgainButton"].exists)
        Thread.sleep(forTimeInterval: 0.8)
        save("06-restart")
        mark("restart")
        Thread.sleep(forTimeInterval: 3.0)
        // Stop the clip while the restarted game is still up, before XCTest backgrounds the app.
        mark("record-stop")
        Thread.sleep(forTimeInterval: 1.5)
    }

    /// Taps on the deck and sky, outside the water, still turn the surfer.
    func testEdgeTapsOutsideThePoolFaceNorthEastSouthWest() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", "1"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        play.tap()
        let facing = app.descendants(matching: .any)["facing"]
        XCTAssertTrue(facing.waitForExistence(timeout: 4))
        let window = app.windows.firstMatch
        // UIKit y-down. These points sit on the sky, the side deck, and the beach.
        let taps: [(CGFloat, CGFloat, String)] = [
            (0.50, 0.04, "north"),
            (0.98, 0.55, "east"),
            (0.50, 0.97, "south"),
            (0.02, 0.55, "west"),
        ]
        for (x, y, side) in taps {
            window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
            let deadline = Date().addingTimeInterval(2)
            var matched = false
            while Date() < deadline {
                if probe(app, "facing") == side {
                    matched = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            XCTAssertTrue(matched, "edge tap \(side) faced \(probe(app, "facing") ?? "nil")")
        }
    }

    /// Reads a probe only while it is still in the tree. Faded callouts are not safe to read.
    private func probe(_ app: XCUIApplication, _ identifier: String) -> String? {
        let element = app.descendants(matching: .any)[identifier]
        guard element.exists else { return nil }
        return element.label
    }

    private func number(in element: XCUIElement) -> Int {
        guard element.exists else { return 0 }
        return Int(element.label.filter(\.isNumber)) ?? 0
    }

    private func waitForMarker(_ name: String, timeout: TimeInterval) -> Bool {
        let url = URL(fileURLWithPath: "/tmp/wavecatch-proof", isDirectory: true).appendingPathComponent(name)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: url.path) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private func mark(_ name: String) {
        let directory = URL(fileURLWithPath: "/tmp/wavecatch-proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("1".utf8))
        let stamp = directory.appendingPathComponent("\(name).time")
        try? String(Date().timeIntervalSince1970).write(to: stamp, atomically: true, encoding: .utf8)
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let image = shot.image
        let pixelsW = image.size.width * image.scale
        let pixelsH = image.size.height * image.scale
        let data = pixelsW >= pixelsH ? shot.pngRepresentation : landscapePNG(image)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = URL(fileURLWithPath: "/tmp/wavecatch-proof", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Native landscape pixels. A portrait framebuffer is rotated so the file is wider than it is tall.
    private func landscapePNG(_ image: UIImage) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let upright = pixelSize.width >= pixelSize.height
        let target = upright ? pixelSize : CGSize(width: pixelSize.height, height: pixelSize.width)
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let drawn = renderer.image { context in
            if upright {
                image.draw(in: CGRect(origin: .zero, size: target))
            } else {
                context.cgContext.translateBy(x: target.width, y: 0)
                context.cgContext.rotate(by: .pi / 2)
                image.draw(in: CGRect(x: 0, y: 0, width: target.height, height: target.width))
            }
        }
        return drawn.pngData() ?? Data()
    }
}

import UIKit
import XCTest

final class WaveCatchUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
    }

    func testFullGameProof() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest", "-seed", "7"]
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft

        let play = app.buttons["playButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["debugGear"].exists)
        save("01-menu")
        mark("record-start")
        Thread.sleep(forTimeInterval: 1.5)
        let started = Date()
        play.tap()

        let score = app.descendants(matching: .any)["score"]
        XCTAssertTrue(score.waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["debugGear"].exists)

        var sawRing = false
        var sawMidgame = false
        var sawCatch = false
        var sawGolden = false
        var previous = 0
        let watchUntil = Date().addingTimeInterval(12)
        while Date() < watchUntil && !(sawRing && sawGolden && sawMidgame && sawCatch) {
            if !sawRing && probe(app, "ringLit") == "1" {
                save("07-swell-ring")
                sawRing = true
            }
            if !sawGolden && probe(app, "sawGolden") == "1" {
                Thread.sleep(forTimeInterval: 0.7)
                save("04-golden")
                sawGolden = true
            }
            let now = number(in: score)
            if now > 0 && !sawMidgame {
                save("02-pool")
                sawMidgame = true
            }
            if now > previous && now >= 2 && !sawCatch {
                save("03-catch")
                sawCatch = true
            }
            previous = now
            Thread.sleep(forTimeInterval: 0.2)
        }

        XCTAssertTrue(sawRing, "the swell ring did not light")
        XCTAssertTrue(sawGolden, "a golden wave should appear in the proof run")
        XCTAssertTrue(sawMidgame, "score never left zero")
        XCTAssertTrue(sawCatch, "a second catch was not shown")

        for side in ["north", "east", "south", "west"] {
            let other = app.otherElements["edge.\(side)"]
            let button = app.buttons["edge.\(side)"]
            XCTAssertTrue(other.waitForExistence(timeout: 4) || button.waitForExistence(timeout: 2), "missing edge.\(side)")
        }

        let niceDeadline = started.addingTimeInterval(25)
        var sawNiceText = false
        while Date() < niceDeadline && !sawNiceText {
            if probe(app, "sawNice") == "1" {
                sawNiceText = true
                break
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertTrue(sawNiceText, "Nice! was not reached")
        let pitchDeadline = Date().addingTimeInterval(2)
        while Date() < pitchDeadline && (probe(app, "maxPitch").flatMap { Int($0.filter(\.isNumber)) } ?? 0) < 3 {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertGreaterThanOrEqual(probe(app, "maxPitch").flatMap { Int($0.filter(\.isNumber)) } ?? 0, 3, "the pitch ladder did not rise")
        XCTAssertEqual(probe(app, "sawGolden"), "1", "a golden wave was not seen")
        XCTAssertEqual(probe(app, "sawBigWave"), "1", "SURGE did not start")

        let again = app.buttons["playAgainButton"]
        var sawMiss = false
        let overDeadline = Date().addingTimeInterval(50)
        while Date() < overDeadline && !again.exists {
            let lives = probe(app, "lives")
            if lives == "2" || lives == "1" || lives == "0" {
                sawMiss = true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
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
        mark("record-stop")
        Thread.sleep(forTimeInterval: 0.8)
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

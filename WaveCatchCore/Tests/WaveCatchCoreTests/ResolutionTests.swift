import XCTest
import WaveCatchCore

final class ResolutionTests: XCTestCase {
    func testCatchShellAndBoard() {
        let shellGame = GameSession(seed: 2, tuning: TuningConfig(scriptedKinds: [.shell]))
        let shell = catchFirst(shellGame)
        XCTAssertEqual(shell.points, 1)
        XCTAssertEqual(shell.combo, 1)
        XCTAssertFalse(shell.close)
        XCTAssertEqual(shellGame.score, 1)
        XCTAssertEqual(shellGame.lives, 3)

        let boardGame = GameSession(seed: 2, tuning: TuningConfig(scriptedKinds: [.board]))
        let board = catchFirst(boardGame)
        XCTAssertEqual(board.kind, .board)
        XCTAssertEqual(board.points, 2)
        XCTAssertEqual(boardGame.score, 2)
    }

    func testSameFrameTapCountsAsACleanCatch() {
        let game = GameSession(seed: 5, tuning: TuningConfig(scriptedKinds: [.shell]))
        _ = firstSpawn(game)
        guard let object = game.liveObjects.first else { return XCTFail("no object") }
        game.setPosition(object.lane)
        let events = advance(game, to: object.arrivalTime + 0.02)
        guard case .caught(_, _, _, let points, _, let close) = events.first(where: { if case .caught = $0 { return true }; return false }) else {
            return XCTFail("expected a catch, got \(events)")
        }
        XCTAssertFalse(close)
        XCTAssertEqual(points, 1)
    }

    func testLateGraceCountsInsideEightyMilliseconds() {
        let game = GameSession(seed: 6, tuning: TuningConfig(scriptedKinds: [.shell]))
        _ = firstSpawn(game)
        guard let object = game.liveObjects.first else { return XCTFail("no object") }
        game.setPosition(object.lane.opposite)
        _ = advance(game, to: object.arrivalTime + 0.04)
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.liveObjects.first?.wobbling, true)
        game.setPosition(object.lane)
        let events = game.tick(dt: 0.01)
        guard case .caught(_, _, _, let points, _, let close) = events.first(where: { if case .caught = $0 { return true }; return false }) else {
            return XCTFail("expected a close catch, got \(events)")
        }
        XCTAssertTrue(close)
        XCTAssertEqual(points, 1)
        XCTAssertEqual(game.combo, 1)
    }

    func testLateGraceExpiresAsAMiss() {
        let game = GameSession(seed: 6, tuning: TuningConfig(scriptedKinds: [.shell]))
        _ = firstSpawn(game)
        guard let object = game.liveObjects.first else { return XCTFail("no object") }
        game.setPosition(object.lane.opposite)
        let events = advance(game, to: object.arrivalTime + Feel.lateGrace + 0.02)
        guard case .missed(_, _, let lives, let lifeLost) = events.first(where: { if case .missed = $0 { return true }; return false }) else {
            return XCTFail("expected a miss, got \(events)")
        }
        XCTAssertTrue(lifeLost)
        XCTAssertEqual(lives, 2)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.score, 0)
    }

    func testTapJustInsideTheGraceStillCounts() {
        let game = GameSession(seed: 8, tuning: TuningConfig(scriptedKinds: [.shell]))
        _ = firstSpawn(game)
        guard let object = game.liveObjects.first else { return XCTFail("no object") }
        game.setPosition(object.lane.opposite)
        _ = advance(game, to: object.arrivalTime + 0.07)
        XCTAssertEqual(game.score, 0)
        game.setPosition(object.lane)
        let events = game.tick(dt: 0.02)
        XCTAssertTrue(events.contains { if case .caught(_, _, _, _, _, true) = $0 { return true }; return false })
    }

    func testMissCostsALifeAndResetsCombo() {
        let game = GameSession(seed: 1, tuning: TuningConfig(scriptedKinds: shells(6)))
        let caught = catchFirst(game)
        XCTAssertEqual(caught.combo, 1)
        let events = missSoonestCatchable(game)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.combo, 0)
        XCTAssertTrue(events.contains { if case .comboChanged(0, _) = $0 { return true }; return false })
        XCTAssertGreaterThan(game.hitStopRemaining, 0.0)
        let frozen = game.time
        let stop = game.hitStopRemaining
        _ = game.tick(dt: 0.04)
        XCTAssertEqual(game.time, frozen, accuracy: 1e-9)
        XCTAssertEqual(game.hitStopRemaining, stop - 0.04, accuracy: 1e-6)
        let previous = game.position
        game.setPosition(previous.opposite)
        XCTAssertEqual(game.position, previous.opposite)
    }

    func testThreeMissesEndTheGame() {
        let game = GameSession(seed: 11, tuning: TuningConfig(scriptedKinds: shells(12)))
        var sawOver = false
        for _ in 0..<3 {
            let events = missSoonestCatchable(game)
            if events.contains(where: { if case .gameOver = $0 { return true }; return false }) {
                sawOver = true
            }
        }
        XCTAssertTrue(sawOver)
        XCTAssertTrue(game.isGameOver)
        XCTAssertEqual(game.lives, 0)
        let score = game.score
        _ = game.tick(dt: 1)
        XCTAssertEqual(game.score, score)
        let parked = game.position
        game.setPosition(parked.opposite)
        XCTAssertEqual(game.position, parked)
    }

    func testStingWhenStayingOnAJellyfish() {
        let game = GameSession(seed: 3, tuning: TuningConfig(scriptedKinds: [.shell, .jellyfish]))
        _ = catchFirst(game)
        XCTAssertEqual(game.combo, 1)
        guard let jelly = waitForKind(game, .jellyfish) else { return XCTFail("no jellyfish") }
        game.setPosition(jelly.lane)
        let events = advance(game, to: jelly.arrivalTime + Feel.stingConfirm + 0.02)
        guard case .stung(_, _, let lives) = events.first(where: { if case .stung = $0 { return true }; return false }) else {
            return XCTFail("expected a sting, got \(events)")
        }
        XCTAssertEqual(lives, 2)
        XCTAssertEqual(game.lives, 2)
        XCTAssertEqual(game.combo, 0)
        XCTAssertGreaterThanOrEqual(game.hitStopRemaining, 0)
    }

    func testHarmlessJellyfishKeepsCombo() {
        let game = GameSession(seed: 3, tuning: TuningConfig(scriptedKinds: [.shell, .jellyfish]))
        _ = catchFirst(game)
        guard let jelly = waitForKind(game, .jellyfish) else { return XCTFail("no jellyfish") }
        game.setPosition(jelly.lane.opposite)
        // Leave early enough that it is a pass, not a last-moment dodge.
        let events = advance(game, to: jelly.arrivalTime + 0.05)
        XCTAssertTrue(events.contains { if case .jellyfishPassed = $0 { return true }; return false })
        XCTAssertFalse(events.contains { if case .stung = $0 { return true }; return false })
        XCTAssertFalse(events.contains { if case .dodged = $0 { return true }; return false })
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.combo, 1)
        XCTAssertEqual(game.score, 1)
    }

    func testLeavingDuringTheStingWindowIsADodge() {
        let game = GameSession(seed: 12, tuning: TuningConfig(scriptedKinds: [.jellyfish]))
        guard let jelly = waitForKind(game, .jellyfish) else { return XCTFail("no jellyfish") }
        game.setPosition(jelly.lane)
        _ = advance(game, to: jelly.arrivalTime + 0.01)
        XCTAssertEqual(game.lives, 3)
        game.setPosition(jelly.lane.opposite)
        let events = game.tick(dt: 0.01)
        XCTAssertTrue(events.contains { if case .dodged = $0 { return true }; return false })
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.combo, 0)
    }

    func testLeavingJustBeforeArrivalIsADodge() {
        let game = GameSession(seed: 13, tuning: TuningConfig(scriptedKinds: [.jellyfish]))
        guard let jelly = waitForKind(game, .jellyfish) else { return XCTFail("no jellyfish") }
        game.setPosition(jelly.lane)
        _ = advance(game, to: jelly.arrivalTime - 0.10)
        game.setPosition(jelly.lane.opposite)
        let events = advance(game, to: jelly.arrivalTime + 0.02)
        XCTAssertTrue(events.contains { if case .dodged = $0 { return true }; return false })
        XCTAssertEqual(game.lives, 3)
    }

    func testMercySilencePhaseDropAndNoJellyfish() {
        var tuning = TuningConfig(jellyfishMultiplier: 2)
        tuning.scriptedKinds = shells(8)
        let game = GameSession(seed: 4, tuning: tuning, startPhase: 5)
        let levelBefore = 4
        let events = missSoonestCatchable(game)
        XCTAssertTrue(events.contains { if case .missed(_, _, _, true) = $0 { return true }; return false })
        let missTime = game.time
        XCTAssertEqual(game.mercyCatchesRemaining, Feel.mercyCatches)
        XCTAssertEqual(game.mercyJellyBlock, Feel.mercyClearSpawns)

        var spawnedAfter: [(at: Double, kind: ObjectKind, travel: Double)] = []
        var steps = 0
        while spawnedAfter.count < 3 && steps < 8000 && !game.isGameOver {
            followCatchables(game)
            for event in game.tick(dt: 0.02) {
                if case .spawned(_, let kind, _, let arrival, let travel) = event {
                    spawnedAfter.append((arrival - travel, kind, travel))
                }
            }
            steps += 1
        }
        XCTAssertGreaterThanOrEqual(spawnedAfter.count, 3)
        XCTAssertGreaterThanOrEqual(spawnedAfter[0].at, missTime + Feel.mercySilence - 0.001)
        let expected = SpeedCurve.travelTime(level: levelBefore - 1, kind: .shell, tuning: tuning)
        XCTAssertEqual(spawnedAfter[0].travel, expected, accuracy: 0.0001)
        XCTAssertTrue(spawnedAfter.prefix(3).allSatisfy { $0.kind != .jellyfish })
        XCTAssertEqual(game.mercyJellyBlock, 0)
    }

    func testMercyFadesAJellyfishThatWouldLandSoon() {
        var faded = false
        for seed in UInt64(1)...UInt64(40) {
            let tuning = TuningConfig(jellyfishMultiplier: 2)
            let game = GameSession(seed: seed, tuning: tuning, startPhase: 8)
            var steps = 0
            while game.time < 20 && !game.isGameOver && steps < 6000 {
                let live = game.liveObjects
                let jellySoon = live.contains {
                    $0.kind == .jellyfish && $0.arrivalTime - game.time > 0.05 && $0.arrivalTime - game.time < 0.85
                }
                let soonCatch = live
                    .filter { $0.kind.isCatchable && $0.arrivalTime - game.time > 0 && $0.arrivalTime - game.time < 0.12 }
                    .min { $0.arrivalTime < $1.arrivalTime }
                if jellySoon, let soonCatch {
                    game.setPosition(soonCatch.lane.opposite)
                    let events = advance(game, to: soonCatch.arrivalTime + Feel.lateGrace + 0.03)
                    if events.contains(where: { if case .jellyfishFaded = $0 { return true }; return false }) {
                        XCTAssertFalse(events.contains { if case .stung = $0 { return true }; return false })
                        faded = true
                        break
                    }
                } else {
                    survives(game)
                    _ = game.tick(dt: 0.02)
                }
                steps += 1
            }
            if faded { break }
        }
        XCTAssertTrue(faded, "a miss should fade a jellyfish due inside the mercy window")
    }

    func testLifeRingScoresThreePoints() {
        let game = GameSession(seed: 1, tuning: TuningConfig(scriptedKinds: [.lifeRing]))
        let caught = catchFirst(game)
        XCTAssertEqual(caught.kind, .lifeRing)
        XCTAssertEqual(caught.points, 3)
        XCTAssertEqual(game.score, 3)
        XCTAssertEqual(game.lives, 3)
    }

    private func catchFirst(_ game: GameSession) -> (points: Int, combo: Int, close: Bool, kind: ObjectKind) {
        _ = firstSpawn(game)
        guard let object = game.liveObjects.first else {
            XCTFail("nothing spawned")
            return (0, 0, false, .shell)
        }
        game.setPosition(object.lane)
        let events = advance(game, to: object.arrivalTime + 0.05)
        guard case .caught(_, _, let kind, let points, let combo, let close) = events.first(where: { if case .caught = $0 { return true }; return false }) else {
            XCTFail("expected a catch, events \(events)")
            return (0, 0, false, .shell)
        }
        return (points, combo, close, kind)
    }

    private func waitForKind(_ game: GameSession, _ kind: ObjectKind) -> LiveObject? {
        var steps = 0
        while steps < 5000 && !game.isGameOver {
            if let found = game.liveObjects.first(where: { $0.kind == kind }) {
                return found
            }
            _ = game.tick(dt: 0.02)
            steps += 1
        }
        return game.liveObjects.first(where: { $0.kind == kind })
    }
}

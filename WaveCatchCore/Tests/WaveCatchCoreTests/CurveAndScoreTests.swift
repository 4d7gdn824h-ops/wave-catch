import XCTest
import WaveCatchCore

final class CurveAndScoreTests: XCTestCase {
    func testSliderDefaultsAndClamp() {
        let tuning = TuningConfig()
        XCTAssertEqual(tuning.speedMultiplier, 1)
        XCTAssertEqual(tuning.spawnRateMultiplier, 1)
        XCTAssertEqual(tuning.jellyfishMultiplier, 1)
        XCTAssertEqual(tuning.bigWaveDuration, 6)
        XCTAssertTrue(tuning.bigWavesEnabled)

        let wild = TuningConfig(
            speedMultiplier: 9,
            spawnRateMultiplier: 0.1,
            jellyfishMultiplier: 4,
            bigWaveDuration: 1
        ).clamped()
        XCTAssertEqual(wild.speedMultiplier, 2)
        XCTAssertEqual(wild.spawnRateMultiplier, 0.5)
        XCTAssertEqual(wild.jellyfishMultiplier, 2)
        XCTAssertEqual(wild.bigWaveDuration, 3)
    }

    func testPublishedSpeedTable() {
        XCTAssertEqual(SpeedCurve.stepInterval(level: 0), 0.60, accuracy: 0.0001)
        XCTAssertEqual(SpeedCurve.stepInterval(level: 9), 0.18, accuracy: 0.0001)
        XCTAssertEqual(SpeedCurve.stepInterval(level: 14), 0.18, accuracy: 0.0001)
        XCTAssertEqual(SpeedCurve.travelTime(level: 0), 2.40, accuracy: 0.0001)
        XCTAssertEqual(SpeedCurve.travelTime(level: 9), 0.72, accuracy: 0.0001)
        let intervals = [1.60, 1.41, 1.24, 1.09, 0.96, 0.84, 0.74, 0.65, 0.58, 0.51, 0.45]
        for level in 0..<intervals.count {
            XCTAssertEqual(SpeedCurve.spawnInterval(level: level), intervals[level], accuracy: 0.015, "I(\(level))")
        }
        XCTAssertEqual(SpeedCurve.spawnInterval(level: 11), 0.40, accuracy: 0.001)
        XCTAssertEqual(SpeedCurve.spawnInterval(level: 20), 0.40, accuracy: 0.001)

        XCTAssertEqual(SpeedCurve.maxOnScreen(level: 0), 2)
        XCTAssertEqual(SpeedCurve.maxOnScreen(level: 2), 2)
        XCTAssertEqual(SpeedCurve.maxOnScreen(level: 3), 3)
        XCTAssertEqual(SpeedCurve.maxOnScreen(level: 6), 4)
        XCTAssertEqual(SpeedCurve.maxOnScreen(level: 9), 5)
        XCTAssertEqual(SpeedCurve.maxOnScreen(level: 14), 5)
    }

    func testKindTravelScalesAndSliders() {
        let shell = SpeedCurve.travelTime(level: 3, kind: .shell, tuning: TuningConfig())
        let board = SpeedCurve.travelTime(level: 3, kind: .board, tuning: TuningConfig())
        let jelly = SpeedCurve.travelTime(level: 3, kind: .jellyfish, tuning: TuningConfig())
        let ring = SpeedCurve.travelTime(level: 3, kind: .lifeRing, tuning: TuningConfig())
        XCTAssertEqual(board, shell, accuracy: 0.0001)
        XCTAssertEqual(jelly, shell, accuracy: 0.0001)
        XCTAssertEqual(ring, shell, accuracy: 0.0001)

        let fast = TuningConfig(speedMultiplier: 2)
        XCTAssertEqual(
            SpeedCurve.travelTime(level: 0, kind: .shell, tuning: fast),
            1.20,
            accuracy: 0.0001
        )
        let busy = TuningConfig(spawnRateMultiplier: 2)
        XCTAssertEqual(SpeedCurve.spawnInterval(level: 0, tuning: busy, bigWave: false), 0.80, accuracy: 0.0001)
        let waveGap = SpeedCurve.spawnInterval(level: 4, tuning: TuningConfig(), bigWave: true)
        let normal = SpeedCurve.spawnInterval(level: 4, tuning: TuningConfig(), bigWave: false)
        XCTAssertEqual(waveGap, max(0.30, 0.50 * normal), accuracy: 0.0001)
    }

    func testComboThresholdsAndRounding() {
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 0), 1)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 4), 1)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 5), 1.5)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 9), 1.5)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 10), 2)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 19), 2)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 20), 3)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 34), 3)
        XCTAssertEqual(ScoreMath.comboMultiplier(for: 35), 4)
        XCTAssertEqual(ScoreMath.callout(for: 5), "Nice!")
        XCTAssertEqual(ScoreMath.callout(for: 10), "Rad!")
        XCTAssertEqual(ScoreMath.callout(for: 20), "Tubular!")
        XCTAssertEqual(ScoreMath.callout(for: 35), "Wave Master!")
        XCTAssertNil(ScoreMath.callout(for: 6))
        XCTAssertEqual(ScoreMath.points(base: 1, multiplier: 1), 1)
        XCTAssertEqual(ScoreMath.points(base: 1, multiplier: 1.5), 2)
        XCTAssertEqual(ScoreMath.points(base: 2, multiplier: 1.5), 3)
        XCTAssertEqual(ScoreMath.points(base: 3, multiplier: 1), 3)
        XCTAssertEqual(ScoreMath.points(base: 1, multiplier: 3), 3)
        XCTAssertEqual(ScoreMath.points(base: 2, multiplier: 4), 8)
    }

    func testPhaseTargetsAndBigWaveSchedule() {
        XCTAssertEqual(PhaseTable.clearTargets, [8, 10, 10, 10, 12, 12, 12, 15, 15, 15])
        XCTAssertEqual(PhaseTable.clearTarget(phaseNumber: 1), 8)
        XCTAssertEqual(PhaseTable.clearTarget(phaseNumber: 11), 15)
        XCTAssertFalse(PhaseTable.bigWaveFollowsClear(of: 3))
        XCTAssertTrue(PhaseTable.bigWaveFollowsClear(of: 4))
        XCTAssertFalse(PhaseTable.bigWaveFollowsClear(of: 5))
        XCTAssertTrue(PhaseTable.bigWaveFollowsClear(of: 7))
        XCTAssertTrue(PhaseTable.bigWaveFollowsClear(of: 10))
        XCTAssertFalse(PhaseTable.bigWaveFollowsClear(of: 11))
        XCTAssertFalse(PhaseTable.bigWaveFollowsClear(of: 12))
        XCTAssertTrue(PhaseTable.bigWaveFollowsClear(of: 13))
        XCTAssertEqual(PhaseTable.mix(phaseNumber: 1).shell, 100)
        XCTAssertEqual(PhaseTable.mix(phaseNumber: 1).jellyfish, 0)
        XCTAssertEqual(PhaseTable.mix(phaseNumber: 2).board, 15)
        XCTAssertEqual(PhaseTable.mix(phaseNumber: 3).ring, 5)
        XCTAssertEqual(PhaseTable.mix(phaseNumber: 4).jellyfish, 5)
    }

    func testSessionStartsAtLowerLeftWithThreeLives() {
        let game = GameSession(seed: 1)
        XCTAssertEqual(game.position, .lowerLeft)
        XCTAssertEqual(game.lives, 3)
        XCTAssertEqual(game.score, 0)
        XCTAssertEqual(game.phaseNumber, 1)
        XCTAssertEqual(game.multiplier, 1)
    }

    func testSpawnUsesCurveAndSpeedRamp() {
        let game = GameSession(seed: 3, tuning: TuningConfig(bigWavesEnabled: false, scriptedKinds: shells(12)))
        let first = firstSpawn(game)
        guard case .spawned(_, let kind, _, _, let travel, _) = first.event else {
            return XCTFail("expected a spawn")
        }
        XCTAssertEqual(kind, .shell)
        XCTAssertEqual(travel, SpeedCurve.travelTime(level: 0, kind: .shell, tuning: TuningConfig()), accuracy: 0.0001)

        var catches = 0
        while catches < 8 && !game.isGameOver {
            followCatchables(game)
            let events = game.tick(dt: 0.02)
            catches += events.filter { if case .caught = $0 { return true }; return false }.count
        }
        XCTAssertEqual(game.phaseNumber, 2)
        var laterTravel: Double?
        var steps = 0
        while laterTravel == nil && steps < 4000 && !game.isGameOver {
            followCatchables(game)
            for event in game.tick(dt: 0.02) {
                if case .spawned(_, .shell, _, _, let travel, _) = event {
                    laterTravel = travel
                }
            }
            steps += 1
        }
        let expected = SpeedCurve.travelTime(level: 1, kind: .shell, tuning: TuningConfig())
        XCTAssertEqual(laterTravel ?? 0, expected, accuracy: 0.0001)
    }

    func testBoardAndJellyfishTravelInSession() {
        let tuning = TuningConfig(scriptedKinds: [.shell, .board, .jellyfish])
        let game = GameSession(seed: 4, tuning: tuning, startPhase: 4)
        var seen = Set<ObjectKind>()
        var steps = 0
        while seen.count < 3 && steps < 5000 && !game.isGameOver {
            followCatchables(game)
            for event in game.tick(dt: 0.02) {
                if case .spawned(_, let kind, _, _, let travel, _) = event {
                    let expected = SpeedCurve.travelTime(level: 3, kind: kind, tuning: tuning)
                    XCTAssertEqual(travel, expected, accuracy: 0.0001, "\(kind)")
                    seen.insert(kind)
                }
            }
            steps += 1
        }
        XCTAssertTrue(seen.contains(.shell))
        XCTAssertTrue(seen.contains(.board))
        XCTAssertTrue(seen.contains(.jellyfish))
    }

    func testClearTargetsAdvanceThePhase() {
        let game = GameSession(seed: 1, tuning: TuningConfig(bigWavesEnabled: false, scriptedKinds: shells(80)))
        var catches = 0
        while catches < 38 && !game.isGameOver {
            followCatchables(game)
            let events = game.tick(dt: 0.05)
            catches += events.filter { if case .caught = $0 { return true }; return false }.count
            if catches == 8 { XCTAssertEqual(game.phaseNumber, 2) }
            if catches == 18 { XCTAssertEqual(game.phaseNumber, 3) }
            if catches == 28 { XCTAssertEqual(game.phaseNumber, 4) }
        }
        XCTAssertEqual(catches, 38)
        XCTAssertEqual(game.phaseNumber, 5)
        XCTAssertFalse(game.isGameOver)
    }

    func testComboScoreAcrossThresholds() {
        let game = GameSession(seed: 9, tuning: TuningConfig(bigWavesEnabled: false, scriptedKinds: shells(60)))
        var catches = 0
        while catches < 50 && !game.isGameOver {
            followCatchables(game)
            let events = game.tick(dt: 0.05)
            for event in events {
                if case .caught(_, _, _, let points, let combo, _) = event {
                    catches += 1
                    let expected = ScoreMath.points(
                        base: 1,
                        multiplier: ScoreMath.comboMultiplier(for: combo)
                    )
                    XCTAssertEqual(points, expected, "catch \(combo)")
                }
            }
        }
        XCTAssertEqual(game.combo, 50)
        XCTAssertEqual(game.multiplier, 4)
        XCTAssertEqual(game.bestCombo, 50)
        // 1–4 ×1, 5–9 ×1.5→2, 10–19 ×2, 20–34 ×3, 35–50 ×4.
        let expectedScore = 4 + 10 + 20 + 45 + 64
        XCTAssertEqual(game.score, expectedScore)
    }

    func testItemsHoldTheirStepUntilTheClockTicks() {
        let game = GameSession(seed: 1, tuning: TuningConfig(scriptedKinds: shells(3)))
        _ = firstSpawn(game)
        guard let spawned = game.liveObjects.first else { return XCTFail("missing object") }
        XCTAssertEqual(spawned.step, 1)
        XCTAssertEqual(spawned.progress, 0, accuracy: 0.0001)
        let held = advance(game, to: game.time + 0.25)
        XCTAssertFalse(held.contains { if case .stepped = $0 { return true }; return false })
        XCTAssertEqual(game.liveObjects.first?.step, 1)
        let moved = advance(game, to: 0.62)
        XCTAssertTrue(moved.contains { if case .stepped = $0 { return true }; return false })
        XCTAssertEqual(game.liveObjects.first?.step, 2)
        XCTAssertEqual(game.liveObjects.first?.progress ?? -1, 0.25, accuracy: 0.0001)
    }

    func testSharedClockAdvancesEveryChute() {
        let game = GameSession(seed: 4, tuning: TuningConfig(scriptedKinds: [.shell, .board]), startPhase: 4)
        var steps = 0
        while game.liveObjects.filter({ $0.kind == .shell || $0.kind == .board }).count < 2 && steps < 4000 && !game.isGameOver {
            followCatchables(game)
            _ = game.tick(dt: 0.02)
            steps += 1
        }
        let before = game.liveObjects.filter { $0.kind == .shell || $0.kind == .board }
        XCTAssertEqual(before.count, 2)
        let events = advance(game, to: game.time + game.stepInterval + 0.02)
        let after = Dictionary(uniqueKeysWithValues: game.liveObjects.map { ($0.id, $0.step) })
        var moved = 0
        for object in before {
            if let step = after[object.id] {
                XCTAssertEqual(step, object.step + 1)
                moved += 1
            }
        }
        XCTAssertGreaterThan(moved, 0)
        XCTAssertTrue(events.contains { if case .stepped = $0 { return true }; return false })
    }

    func testTelegraphLead() {
        let game = GameSession(seed: 1, tuning: TuningConfig(scriptedKinds: shells(2)))
        _ = firstSpawn(game)
        guard let arrival = game.liveObjects.first?.arrivalTime else {
            return XCTFail("missing object")
        }
        let step = SpeedCurve.stepInterval(level: 0)
        let before = advance(game, to: arrival - step - 0.05)
        XCTAssertFalse(before.contains { if case .telegraph = $0 { return true }; return false })
        XCTAssertEqual(game.liveObjects.first?.step, 3)
        let after = advance(game, to: arrival - step + 0.02)
        XCTAssertTrue(after.contains { if case .telegraph = $0 { return true }; return false })
        XCTAssertEqual(game.liveObjects.first?.telegraph, true)
        XCTAssertEqual(game.liveObjects.first?.step, 4)
        XCTAssertEqual(SpeedCurve.telegraphLead(travel: 2.4), 0.6, accuracy: 0.0001)
    }

    func testGoldenShellIsWorthFiveAndSpotlightSpawnsOne() {
        let scripted = GameSession(seed: 3, tuning: TuningConfig(scriptedKinds: [.goldenShell]))
        _ = firstSpawn(scripted)
        guard let object = scripted.liveObjects.first else { return XCTFail("no shell") }
        scripted.setPosition(object.lane)
        let caught = advance(scripted, to: object.arrivalTime + 0.05)
        let points = caught.compactMap { event -> Int? in
            if case .caught(_, _, _, let awarded, _, _) = event { return awarded }
            return nil
        }
        XCTAssertEqual(points.first, 5)

        let spotlight = GameSession(seed: 9, tuning: TuningConfig(spotlightGoldenShell: true), startPhase: 1)
        var kinds: [ObjectKind] = []
        var steps = 0
        while kinds.count < 3 && steps < 4000 {
            for event in spotlight.tick(dt: 0.05) {
                if case .spawned(_, let kind, _, _, _, _) = event {
                    kinds.append(kind)
                }
            }
            steps += 1
        }
        XCTAssertEqual(kinds.first, .shell)
        XCTAssertEqual(kinds.dropFirst().first, .goldenShell)
    }
}

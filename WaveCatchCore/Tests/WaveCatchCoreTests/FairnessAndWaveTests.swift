import XCTest
import WaveCatchCore

final class FairnessAndWaveTests: XCTestCase {
    func testDeterministicWithTheSameSeed() {
        let first = runAutopilot(seed: 42, seconds: 25)
        let second = runAutopilot(seed: 42, seconds: 25)
        XCTAssertEqual(first, second)
        XCTAssertFalse(first.isEmpty)
    }

    func testDifferentSeedsDiverge() {
        var left = SeededRNG(seed: 1)
        var right = SeededRNG(seed: 1)
        var other = SeededRNG(seed: 2)
        XCTAssertEqual(left.nextUInt64(), right.nextUInt64())
        XCTAssertNotEqual(left.nextUInt64(), other.nextUInt64())

        let a = runAutopilot(seed: 1, seconds: 12)
        let b = runAutopilot(seed: 2, seconds: 12)
        XCTAssertNotEqual(a, b)
    }

    func testPhaseOneArrivalsStayWellApart() {
        let game = GameSession(seed: 21, tuning: TuningConfig(scriptedKinds: shells(16)))
        var arrivals: [Double] = []
        let events = play(game, for: 18, dt: 0.05) { followCatchables($0) }
        for event in events {
            if case .spawned(_, _, _, let arrival, _) = event {
                arrivals.append(arrival)
            }
        }
        XCTAssertGreaterThan(arrivals.count, 4)
        for left in arrivals.indices {
            for right in (left + 1)..<arrivals.count {
                XCTAssertGreaterThanOrEqual(abs(arrivals[left] - arrivals[right]), 1.2 - 0.001)
            }
        }
        XCTAssertFalse(game.stalled)
    }

    func testFairnessHoldsAcrossSeeds() {
        for seed in [UInt64(1), 7, 42, 99, 256] {
            let tuning = TuningConfig(speedMultiplier: 1.5, spawnRateMultiplier: 1.5, jellyfishMultiplier: 1.5)
            let game = GameSession(seed: seed, tuning: tuning, startPhase: 8)
            var spawns: [(kind: ObjectKind, lane: Lane, arrival: Double)] = []
            var catchableLanes: [Lane] = []
            let events = play(game, for: 40, dt: 0.05) { survives($0) }
            for event in events {
                if case .spawned(_, let kind, let lane, let arrival, _) = event {
                    spawns.append((kind, lane, arrival))
                    if kind.isCatchable { catchableLanes.append(lane) }
                }
            }
            XCTAssertGreaterThan(spawns.count, 15, "seed \(seed)")
            XCTAssertGreaterThan(spawns.filter { $0.kind == .jellyfish }.count, 0, "seed \(seed)")
            assertFair(spawns, catchableLanes: catchableLanes, seed: seed)
            XCTAssertFalse(game.stalled, "seed \(seed)")
            XCTAssertFalse(game.isGameOver, "autopilot died on seed \(seed)")
        }
    }

    func testOnScreenCap() {
        let early = GameSession(seed: 2, tuning: TuningConfig(scriptedKinds: shells(20)))
        _ = play(early, for: 8, dt: 0.02) { followCatchables($0) }
        // Re-run while sampling the live set.
        let paced = GameSession(seed: 2, tuning: TuningConfig(scriptedKinds: shells(30)))
        var steps = 0
        while paced.time < 10 && steps < 5000 {
            followCatchables(paced)
            _ = paced.tick(dt: 0.02)
            XCTAssertLessThanOrEqual(paced.liveObjects.count, SpeedCurve.maxOnScreen(level: max(0, paced.phaseIndex)))
            steps += 1
        }

        let fastTuning = TuningConfig(speedMultiplier: 2, spawnRateMultiplier: 2)
        let late = GameSession(seed: 8, tuning: fastTuning, startPhase: 10)
        steps = 0
        while late.time < 20 && !late.isGameOver && steps < 8000 {
            survives(late)
            _ = late.tick(dt: 0.02)
            XCTAssertLessThanOrEqual(late.liveObjects.count, 5)
            steps += 1
        }
    }

    func testDemoSpotlightSpawnsAJellyfishEarly() {
        let tuning = TuningConfig(scriptedKinds: [], demoSpotlightJellyfish: true)
        let game = GameSession(seed: 7, tuning: tuning, startPhase: 1)
        var kinds: [ObjectKind] = []
        var steps = 0
        while kinds.count < 4 && steps < 4000 {
            for event in game.tick(dt: 0.05) {
                if case .spawned(_, let kind, _, _, _) = event {
                    kinds.append(kind)
                }
            }
            steps += 1
        }
        XCTAssertEqual(kinds.prefix(2).allSatisfy { $0 == .shell }, true)
        XCTAssertEqual(kinds[2], .jellyfish)
    }

    func testBigWaveScheduleDurationAndNoLifeLoss() {
        let tuning = TuningConfig(bigWaveDuration: 3.5, scriptedKinds: shells(80))
        let game = GameSession(seed: 5, tuning: tuning, startPhase: 4)
        var catches = 0
        var warningTime: Double?
        var startTime: Double?
        var endTime: Double?
        var kindsDuringWave: [ObjectKind] = []
        var waveOpen = false
        var firstWaveCatch: (points: Int, combo: Int, kind: ObjectKind)?
        var livesAtActive: Int?
        var comboAtActive: Int?
        var missedInWave = false
        var bonusLost = false
        var catchAfterLoss: (points: Int, combo: Int, kind: ObjectKind)?

        var steps = 0
        while steps < 20000 && endTime == nil {
            if waveOpen && !missedInWave && game.bigWavePhase == .active && (comboAtActive ?? 0) > 0 && firstWaveCatch != nil {
                if let target = game.liveObjects.filter({ $0.kind.isCatchable }).min(by: { $0.arrivalTime < $1.arrivalTime }) {
                    game.setPosition(target.lane.opposite)
                }
            } else if !missedInWave {
                followCatchables(game)
            } else if game.bigWavePhase == .active {
                followCatchables(game)
            } else {
                followCatchables(game)
            }

            let mark = game.time
            let events = game.tick(dt: 0.02)
            for event in events {
                switch event {
                case .caught(_, _, let kind, let points, let combo, _):
                    catches += 1
                    if game.bigWavePhase == .active && bigWaveBonusStillOn(events) && firstWaveCatch == nil && !bonusLost {
                        firstWaveCatch = (points, combo, kind)
                    }
                    if missedInWave && catchAfterLoss == nil && game.bigWavePhase == .active {
                        catchAfterLoss = (points, combo, kind)
                    }
                case .bigWaveWarning:
                    if warningTime == nil { warningTime = max(game.time, mark) }
                case .bigWaveStart:
                    startTime = max(game.time, mark)
                    waveOpen = true
                    livesAtActive = game.lives
                    comboAtActive = game.combo
                case .spawned(_, let kind, _, _, _):
                    if waveOpen && endTime == nil {
                        kindsDuringWave.append(kind)
                    }
                case .missed(_, _, _, let lifeLost):
                    if waveOpen && game.bigWavePhase == .active {
                        XCTAssertFalse(lifeLost)
                        missedInWave = true
                    }
                case .bigWaveBonusLost:
                    bonusLost = true
                case .bigWaveEnd:
                    endTime = max(game.time, mark)
                    waveOpen = false
                default:
                    break
                }
            }
            steps += 1
            if game.isGameOver { break }
        }

        XCTAssertEqual(catches >= 10, true)
        XCTAssertNotNil(warningTime)
        XCTAssertNotNil(startTime)
        XCTAssertNotNil(endTime)
        if let warningTime, let startTime {
            XCTAssertEqual(startTime - warningTime, Feel.bigWaveWarning, accuracy: 0.05)
        }
        if let startTime, let endTime {
            XCTAssertEqual(endTime - startTime, 3.5, accuracy: 0.05)
        }
        XCTAssertFalse(kindsDuringWave.contains(.jellyfish))
        XCTAssertNotNil(firstWaveCatch)
        if let firstWaveCatch {
            let expected = ScoreMath.points(
                base: firstWaveCatch.kind.basePoints,
                multiplier: ScoreMath.comboMultiplier(for: firstWaveCatch.combo) + 2
            )
            XCTAssertEqual(firstWaveCatch.points, expected)
        }
        XCTAssertTrue(missedInWave)
        XCTAssertTrue(bonusLost)
        XCTAssertEqual(game.lives, livesAtActive)
        if let catchAfterLoss {
            let withBonus = ScoreMath.points(
                base: catchAfterLoss.kind.basePoints,
                multiplier: ScoreMath.comboMultiplier(for: catchAfterLoss.combo) + 2
            )
            let plain = ScoreMath.points(
                base: catchAfterLoss.kind.basePoints,
                multiplier: ScoreMath.comboMultiplier(for: catchAfterLoss.combo)
            )
            XCTAssertEqual(catchAfterLoss.points, plain)
            XCTAssertNotEqual(catchAfterLoss.points, withBonus)
        } else {
            XCTFail("expected a catch after the wave bonus dropped")
        }
    }

    func testBigWaveFollowsLaterPhaseClears() {
        XCTAssertEqual(waveStartsAfterClear(startPhase: 4, catches: 10), true)
        XCTAssertEqual(waveStartsAfterClear(startPhase: 5, catches: 12), false)
        XCTAssertEqual(waveStartsAfterClear(startPhase: 7, catches: 12), true)
        XCTAssertEqual(waveStartsAfterClear(startPhase: 10, catches: 15), true)
        XCTAssertEqual(waveStartsAfterClear(startPhase: 12, catches: 15), false)
        XCTAssertEqual(waveStartsAfterClear(startPhase: 13, catches: 15), true)
    }

    func testBreatherHasNoJellyfishAndSlowerTravel() {
        let game = GameSession(seed: 6, tuning: TuningConfig(scriptedKinds: shells(40)), startPhase: 4)
        var ended = false
        var phaseAtEnd = 1
        var steps = 0
        while !ended && steps < 15000 && !game.isGameOver {
            followCatchables(game)
            let events = game.tick(dt: 0.05)
            if events.contains(where: { if case .bigWaveEnd = $0 { return true }; return false }) {
                ended = true
                phaseAtEnd = game.phaseIndex
            }
            steps += 1
        }
        XCTAssertTrue(ended)
        XCTAssertEqual(game.bigWavePhase, .breather)
        XCTAssertEqual(game.speedLevel, max(0, game.phaseIndex - 2))
        var checked = 0
        steps = 0
        while checked < 2 && game.bigWavePhase == .breather && steps < 4000 {
            for event in game.tick(dt: 0.02) {
                if case .spawned(_, let kind, _, _, let travel) = event {
                    XCTAssertNotEqual(kind, .jellyfish)
                    XCTAssertEqual(game.bigWavePhase, .breather)
                    XCTAssertEqual(game.speedLevel, max(0, phaseAtEnd - 2))
                    let expected = SpeedCurve.travelTime(level: game.speedLevel, kind: kind, tuning: game.tuning)
                    XCTAssertEqual(travel, expected, accuracy: 0.0001)
                    let full = SpeedCurve.travelTime(level: phaseAtEnd, kind: kind, tuning: game.tuning)
                    XCTAssertGreaterThanOrEqual(travel + 0.0001, full)
                    checked += 1
                }
            }
            steps += 1
        }
        XCTAssertGreaterThanOrEqual(checked, 1)
    }

    private func waveStartsAfterClear(startPhase: Int, catches needed: Int) -> Bool {
        let game = GameSession(
            seed: 1,
            tuning: TuningConfig(scriptedKinds: shells(needed + 5)),
            startPhase: startPhase
        )
        var catches = 0
        var started = false
        var steps = 0
        while catches < needed && steps < 20000 && !game.isGameOver {
            followCatchables(game)
            let events = game.tick(dt: 0.05)
            if events.contains(where: { if case .bigWaveWarning = $0 { return true }; return false }) {
                started = true
            }
            catches += events.filter { if case .caught = $0 { return true }; return false }.count
            steps += 1
        }
        return started && catches == needed
    }

    private func bigWaveBonusStillOn(_ events: [GameEvent]) -> Bool {
        !events.contains { if case .bigWaveBonusLost = $0 { return true }; return false }
    }

    private func runAutopilot(seed: UInt64, seconds: Double) -> [GameEvent] {
        let tuning = TuningConfig(speedMultiplier: 1.25, spawnRateMultiplier: 1.25)
        let game = GameSession(seed: seed, tuning: tuning, startPhase: 6)
        return play(game, for: seconds, dt: 0.05) { survives($0) }
    }

    private func assertFair(
        _ spawns: [(kind: ObjectKind, lane: Lane, arrival: Double)],
        catchableLanes: [Lane],
        seed: UInt64
    ) {
        let catchables = spawns.filter { $0.kind.isCatchable }
        for left in catchables.indices {
            for right in (left + 1)..<catchables.count {
                let gap = abs(catchables[left].arrival - catchables[right].arrival)
                if catchables[left].lane == catchables[right].lane {
                    XCTAssertGreaterThanOrEqual(gap, Feel.catchableGap - 0.001, "same lane seed \(seed)")
                } else if Lane.isOppositeDiagonal(catchables[left].lane, catchables[right].lane) {
                    XCTAssertGreaterThanOrEqual(gap, Feel.diagonalGap - 0.001, "diagonal seed \(seed)")
                } else {
                    XCTAssertGreaterThanOrEqual(gap, Feel.catchableGap - 0.001, "adjacent seed \(seed)")
                }
            }
        }
        let jellies = spawns.filter { $0.kind == .jellyfish }
        for jelly in jellies {
            for other in spawns where other.lane == jelly.lane && other.arrival != jelly.arrival {
                XCTAssertGreaterThanOrEqual(
                    abs(jelly.arrival - other.arrival),
                    Feel.jellyfishGap - 0.001,
                    "jelly lane seed \(seed)"
                )
            }
        }
        let sorted = jellies.sorted { $0.arrival < $1.arrival }
        for start in sorted.indices {
            var lanes = Set<Lane>()
            for next in start..<sorted.count {
                if sorted[next].arrival - sorted[start].arrival > Feel.jellyfishCluster + 1e-6 { break }
                lanes.insert(sorted[next].lane)
            }
            XCTAssertLessThan(lanes.count, 3, "cluster seed \(seed)")
        }
        var streakLane: Lane?
        var streak = 0
        for lane in catchableLanes {
            if lane == streakLane {
                streak += 1
            } else {
                streakLane = lane
                streak = 1
            }
            XCTAssertLessThanOrEqual(streak, Feel.maxLaneStreak, "streak seed \(seed)")
        }
    }
}

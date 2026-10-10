import XCTest
import WaveCatchCore

final class WavePoolTests: XCTestCase {
    func testFacingASwellCatchesAndLookingAwayMisses() {
        let hit = drive(scriptedKinds: [.swell], scriptedSides: [.north], face: .north)
        XCTAssertTrue(hit.contains { if case .caught(_, .north, .swell, _, _, _) = $0 { return true }; return false })

        let miss = WavePoolSession(seed: 2, scriptedKinds: [.swell], scriptedSides: [.north])
        miss.face(.south)
        let missed = run(miss, until: { events in
            events.contains { if case .missed = $0 { return true }; return false }
        }, limit: 30)
        XCTAssertTrue(missed.contains { if case .missed(_, .north, 2, true) = $0 { return true }; return false })
        XCTAssertEqual(miss.lives, 2)
        XCTAssertEqual(miss.combo, 0)
    }

    func testLateGraceStillCountsAsClose() {
        let session = WavePoolSession(seed: 3, scriptedKinds: [.swell], scriptedSides: [.north])
        session.face(.south)
        var arrived = false
        for _ in 0..<24 {
            session.tick(dt: session.stepInterval)
            if session.liveWaves.contains(where: { $0.step >= 5 && $0.side == .north }) {
                arrived = true
                break
            }
        }
        XCTAssertTrue(arrived)
        session.face(.north)
        let events = session.tick(dt: 0.04)
        XCTAssertTrue(events.contains { if case .caught(_, _, _, _, _, true) = $0 { return true }; return false })
    }

    func testChopWipeoutAndDodge() {
        let wipe = drive(scriptedKinds: [.chop], scriptedSides: [.east], face: .east, phase: 4)
        XCTAssertTrue(wipe.contains { if case .wiped(_, .east, 2, true) = $0 { return true }; return false })

        let slip = drive(scriptedKinds: [.chop], scriptedSides: [.east], face: .north, phase: 4)
        XCTAssertTrue(slip.contains { if case .dodged(_, .east) = $0 { return true }; return false })
        XCTAssertFalse(slip.contains { if case .wiped = $0 { return true }; return false })
    }

    func testMercySkipsSpawnsDropsSpeedAndBlocksChop() {
        let session = WavePoolSession(
            seed: 4,
            startPhase: 4,
            scriptedKinds: [.swell, .chop, .chop, .chop, .chop],
            scriptedSides: [.north, .north, .south, .north, .south]
        )
        session.face(.south)
        _ = run(session, until: { $0.contains { if case .missed = $0 { return true }; return false } }, limit: 30)
        let slowed = SpeedCurve.stepInterval(level: 2)
        XCTAssertEqual(session.stepInterval, slowed, accuracy: 0.0001)
        XCTAssertEqual(session.mercyCatchesRemaining, Feel.mercyCatches)
        var spawned: [WaveKind] = []
        var quietSteps = 0
        for _ in 0..<12 {
            let events = session.tick(dt: session.stepInterval)
            let births = events.compactMap { event -> WaveKind? in
                if case .spawned(_, let kind, _, _) = event { return kind }
                return nil
            }
            if births.isEmpty { quietSteps += 1 } else { break }
            spawned += births
        }
        XCTAssertGreaterThanOrEqual(quietSteps, 2)
        for _ in 0..<16 where spawned.count < 3 {
            let events = session.tick(dt: session.stepInterval)
            spawned += events.compactMap { event in
                if case .spawned(_, let kind, _, _) = event { return kind }
                return nil
            }
        }
        XCTAssertGreaterThanOrEqual(spawned.count, 3)
        XCTAssertTrue(spawned.prefix(3).allSatisfy { $0 != .chop })
    }

    func testPhaseOneStaysOnNorthAndSouth() {
        let session = WavePoolSession(seed: 11, startPhase: 1)
        var sides = Set<Side>()
        for _ in 0..<40 {
            for event in session.tick(dt: session.stepInterval) {
                if case .spawned(_, _, let side, _) = event { sides.insert(side) }
            }
        }
        XCTAssertFalse(sides.isEmpty)
        XCTAssertTrue(sides.isSubset(of: [.north, .south]))
    }

    func testFairnessHoldsAcrossSeeds() {
        for seed in 1...12 {
            for phase in [1, 5, 6] {
                let session = WavePoolSession(seed: UInt64(seed), startPhase: phase)
                var arrivals: [(tick: Int, side: Side, kind: WaveKind)] = []
                for _ in 0..<80 {
                    for event in session.tick(dt: session.stepInterval) {
                        if case .spawned(_, let kind, let side, let tick) = event {
                            arrivals.append((tick, side, kind))
                        }
                    }
                    let live = session.liveWaves
                    XCTAssertLessThanOrEqual(live.count, 4, "seed \(seed) phase \(phase)")
                    let patterned = live.contains { $0.fromPattern }
                    if session.bigWavePhase != .active && !patterned {
                        XCTAssertLessThanOrEqual(live.count, PoolTables.maxWaves(phase: session.phaseNumber))
                    }
                    for side in Side.allCases {
                        let rows = live.filter { $0.side == side }.map(\.step).sorted()
                        guard rows.count > 1 else { continue }
                        for index in 1..<rows.count {
                            XCTAssertGreaterThan(rows[index] - rows[index - 1], 1, "seed \(seed) \(side)")
                        }
                    }
                    let chops = live.filter { $0.kind == .chop }
                    let catchables = live.filter { $0.kind.isCatchable }
                    for chop in chops {
                        XCTAssertFalse(catchables.contains { $0.arrivalTick == chop.arrivalTick })
                    }
                }
                let catchables = arrivals.filter { $0.kind.isCatchable }
                let gap = phase >= 5 ? 1 : 2
                for index in 1..<catchables.count {
                    let delta = catchables[index].tick - catchables[index - 1].tick
                    XCTAssertGreaterThanOrEqual(delta, gap, "seed \(seed) phase \(phase)")
                    if phase < 6 && delta == 1 {
                        XCTAssertNotEqual(catchables[index].side, catchables[index - 1].side.opposite)
                    }
                }
            }
        }
    }

    func testPhaseTenMixAndEarlierGates() {
        let early = PoolTables.mix(phase: 2)
        XCTAssertEqual(early.chop, 0)
        XCTAssertEqual(early.set, 0)
        XCTAssertEqual(early.pattern, 0)
        let golden = PoolTables.mix(phase: 3)
        XCTAssertEqual(golden.golden, 0.03, accuracy: 0.0001)
        XCTAssertEqual(golden.chop, 0)
        let chop = PoolTables.mix(phase: 4)
        XCTAssertGreaterThan(chop.chop, 0)
        let end = PoolTables.mix(phase: 10)
        XCTAssertEqual(end.swell, 0.55, accuracy: 0.0001)
        XCTAssertEqual(end.set, 0.15, accuracy: 0.0001)
        XCTAssertEqual(end.golden, 0.03, accuracy: 0.0001)
        XCTAssertEqual(end.chop, 0.18, accuracy: 0.0001)
        XCTAssertEqual(end.pattern, 0.09, accuracy: 0.0001)
        XCTAssertEqual(PoolTables.mix(phase: 5).pattern, 0.20, accuracy: 0.0001)
        XCTAssertEqual(PoolTables.maxWaves(phase: 1), 1)
        XCTAssertEqual(PoolTables.maxWaves(phase: 10), 4)
    }

    func testSpinAfterFourSidesAndSurgeAfterPhaseFour() {
        let spin = WavePoolSession(seed: 8, startPhase: 6, forcedPattern: .clockwise)
        var spun = false
        for _ in 0..<50 {
            if let side = spin.liveWaves.filter({ $0.kind.isCatchable }).max(by: { $0.step < $1.step })?.side {
                spin.face(side)
            }
            if spin.tick(dt: spin.stepInterval).contains(where: { if case .spin = $0 { return true }; return false }) {
                spun = true
                break
            }
        }
        XCTAssertTrue(spun)
        XCTAssertGreaterThanOrEqual(spin.score, 5)

        let surge = WavePoolSession(
            seed: 9,
            startPhase: 4,
            scriptedKinds: Array(repeating: .swell, count: 12),
            scriptedSides: Array(repeating: .north, count: 12)
        )
        surge.face(.north)
        var warned = false
        for _ in 0..<80 {
            if surge.tick(dt: surge.stepInterval).contains(where: { if case .surgeWarning = $0 { return true }; return false }) {
                warned = true
                break
            }
        }
        XCTAssertTrue(warned)
        XCTAssertEqual(surge.bigWavePhase, .warning)
    }

    func testGoldenHourDoublesTheNextCatchAndSpotlightSurge() {
        let session = WavePoolSession(
            seed: 10,
            startPhase: 6,
            scriptedKinds: [.goldenWave, .swell],
            scriptedSides: [.north, .south]
        )
        session.face(.north)
        let first = run(session, until: { $0.contains { if case .goldenHour = $0 { return true }; return false } }, limit: 30)
        XCTAssertTrue(first.contains { if case .caught(_, _, .goldenWave, 5, _, _) = $0 { return true }; return false })
        XCTAssertGreaterThan(session.goldenHourRemaining, 0)
        session.face(.south)
        let second = run(session, until: { $0.contains { if case .caught(_, _, .swell, _, _, _) = $0 { return true }; return false } }, limit: 30)
        XCTAssertTrue(second.contains { if case .caught(_, _, .swell, 2, _, _) = $0 { return true }; return false })

        let spotlight = WavePoolSession(seed: 12, tuning: TuningConfig(spotlightGoldenWave: true, spotlightSurge: true))
        var sawGolden = false
        var sawSurge = false
        for _ in 0..<40 {
            if let side = spotlight.suggestedSide() { spotlight.face(side) }
            for event in spotlight.tick(dt: spotlight.stepInterval) {
                if case .spawned(_, .goldenWave, _, _) = event { sawGolden = true }
                if case .surgeWarning = event { sawSurge = true }
            }
            if sawGolden && sawSurge { break }
        }
        XCTAssertTrue(sawGolden)
        XCTAssertTrue(sawSurge)
    }

    /// The proof autopilot has to fit the screenshot windows: ring and golden early, Nice by 25s, then a miss and game over.
    func testProofAutopilotFitsTheScreenshotWindows() {
        var tuning = TuningConfig()
        tuning.spotlightGoldenWave = true
        tuning.spotlightSurge = true
        let pool = WavePoolSession(seed: 7, tuning: tuning, startPhase: 1)
        var proofNice = false
        var proofDeath = false
        var sawGolden = false
        var sawRing = false
        var sawSurge = false
        var sawMiss = false
        var niceAt = -1.0
        var overAt = -1.0
        var time = 0.0
        let dt = 1.0 / 60.0
        while time < 90, overAt < 0 {
            let live = pool.liveWaves
            if !proofDeath {
                if let side = pool.suggestedSide() { pool.face(side) }
                if let chop = live.filter({ $0.kind == .chop }).min(by: { $0.arrivalTick < $1.arrivalTick }),
                   chop.side == pool.facing, chop.step >= 4,
                   let away = Side.allCases.first(where: { candidate in
                       candidate != chop.side && !live.contains { $0.kind == .chop && $0.side == candidate }
                   }) {
                    pool.face(away)
                }
            } else if let side = pool.suggestedSide() {
                pool.face(side.opposite)
            }
            let events = pool.tick(dt: dt)
            if pool.liveWaves.contains(where: { $0.kind == .goldenWave }) { sawGolden = true }
            if !pool.ringSides.isEmpty { sawRing = true }
            if pool.bigWavePhase != .idle { sawSurge = true }
            if pool.lives < 3 { sawMiss = true }
            if pool.combo >= 5 {
                proofNice = true
                if niceAt < 0 { niceAt = time }
            }
            if proofNice, pool.bigWavePhase == .breather { proofDeath = true }
            if events.contains(where: { if case .gameOver = $0 { return true }; return false }) {
                overAt = time
            }
            time += dt
        }
        XCTAssertTrue(sawRing)
        XCTAssertTrue(sawGolden)
        XCTAssertGreaterThan(niceAt, 0)
        XCTAssertLessThan(niceAt, 22, "Nice landed at \(niceAt)")
        XCTAssertTrue(sawSurge)
        XCTAssertTrue(sawMiss)
        XCTAssertGreaterThan(overAt, niceAt)
        XCTAssertLessThan(overAt - niceAt, 45, "game over at \(overAt), nice at \(niceAt)")
    }

    private func drive(
        scriptedKinds: [WaveKind],
        scriptedSides: [Side],
        face: Side,
        phase: Int = 1
    ) -> [PoolEvent] {
        let session = WavePoolSession(
            seed: 1,
            startPhase: phase,
            scriptedKinds: scriptedKinds,
            scriptedSides: scriptedSides
        )
        session.face(face)
        return run(session, until: { events in
            events.contains { event in
                switch event {
                case .caught, .missed, .wiped, .dodged: return true
                default: return false
                }
            }
        }, limit: 30)
    }

    private func run(_ session: WavePoolSession, until match: ([PoolEvent]) -> Bool, limit: Int) -> [PoolEvent] {
        var all: [PoolEvent] = []
        for _ in 0..<limit {
            let events = session.tick(dt: session.stepInterval)
            all += events
            if match(events) { break }
        }
        return all
    }
}

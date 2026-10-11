import XCTest
import WaveCatchCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

    func testPhaseOneSpawnsSixWavesInTwentyTicks() {
        let session = WavePoolSession(seed: 7, startPhase: 1)
        var spawns = 0
        var firstWhump: Double?
        for _ in 0..<20 {
            if let side = session.suggestedSide() { session.face(side) }
            for event in session.tick(dt: session.stepInterval) {
                if case .whump = event, firstWhump == nil {
                    firstWhump = session.time
                }
                if case .spawned = event { spawns += 1 }
            }
        }
        XCTAssertLessThan(firstWhump ?? 9, 1, "the first vent blink was late")
        XCTAssertGreaterThanOrEqual(spawns, 6, "phase 1 spawned \(spawns) waves in 20 ticks")
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
        XCTAssertEqual(PoolTables.maxWaves(phase: 1), 2)
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

    func testDeckEdgesOutsideThePoolMapToNorthEastSouthWest() {
        // A 1000×500 scene. The water is the centered 86% band, narrower than the deck.
        let width = 1000.0
        let height = 500.0
        let poolH = height * 0.86
        let poolW = min(width * 0.62, poolH * 1.15)
        let poolMinX = (width - poolW) / 2
        let poolMaxX = poolMinX + poolW
        let poolMinY = height * 0.04
        let poolMaxY = poolMinY + poolH
        let outside: [(Double, Double, Side)] = [
            (width / 2, height - 2, .north),
            (width - 2, height / 2, .east),
            (width / 2, 2, .south),
            (2, height / 2, .west),
        ]
        for (x, y, side) in outside {
            let inWater = x >= poolMinX && x <= poolMaxX && y >= poolMinY && y <= poolMaxY
            XCTAssertFalse(inWater, "\(side) sample landed in the water")
            XCTAssertEqual(PoolInput.side(x: x, y: y, width: width, height: height), side)
        }
        // Sky strip and the far deck corners still belong to a zone.
        XCTAssertEqual(PoolInput.side(x: width * 0.5, y: height * 0.99, width: width, height: height), .north)
        XCTAssertEqual(PoolInput.side(x: width * 0.99, y: height * 0.08, width: width, height: height), .east)
        XCTAssertEqual(PoolInput.side(x: width * 0.5, y: height * 0.01, width: width, height: height), .south)
        XCTAssertEqual(PoolInput.side(x: width * 0.01, y: height * 0.92, width: width, height: height), .west)
    }

    func testNosePointsTowardTheFacedSide() {
        let expected: [Side: (x: Double, y: Double)] = [
            .north: (0, 1),
            .east: (1, 0),
            .south: (0, -1),
            .west: (-1, 0),
        ]
        for side in Side.allCases {
            let nose = PoolInput.noseVector(facing: side)
            let want = expected[side]!
            XCTAssertEqual(nose.x, want.x, accuracy: 0.0001, "\(side) x")
            XCTAssertEqual(nose.y, want.y, accuracy: 0.0001, "\(side) y")
            let angle = PoolInput.noseRotation(facing: side)
            XCTAssertEqual(nose.x, -sin(angle), accuracy: 0.0001)
            XCTAssertEqual(nose.y, cos(angle), accuracy: 0.0001)
        }
        // Facing east puts the nose on the right, never on the left.
        XCTAssertGreaterThan(PoolInput.noseVector(facing: .east).x, 0.5)
        XCTAssertEqual(PoolInput.noseRotation(facing: .north), 0, accuracy: 0.0001)
        XCTAssertEqual(PoolInput.noseRotation(facing: .east), -.pi / 2, accuracy: 0.0001)
    }

    func testPhaseOneClockThenTheExistingCurve() {
        let opening = WavePoolSession(seed: 1, startPhase: 1)
        XCTAssertEqual(opening.stepInterval, 0.75, accuracy: 0.0001)
        XCTAssertEqual(SpeedCurve.stepInterval(level: 0), 0.60, accuracy: 0.0001)
        let phase2 = WavePoolSession(seed: 1, startPhase: 2)
        XCTAssertEqual(phase2.stepInterval, SpeedCurve.stepInterval(level: 1), accuracy: 0.0001)
    }

    func testPhaseOneSpawnsEveryThreeTicksFromTheFacedSide() {
        let session = WavePoolSession(seed: 7, startPhase: 1)
        session.face(.east)
        var spawnTicks: [Int] = []
        var sides: [Side] = []
        for _ in 0..<24 {
            for event in session.tick(dt: session.stepInterval) {
                if case .spawned(_, _, let side, let arrival) = event {
                    spawnTicks.append(arrival - 4)
                    sides.append(side)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(sides.count, 4)
        let opening = Array(spawnTicks.prefix(5))
        XCTAssertGreaterThanOrEqual(opening.count, 5, "ticks \(spawnTicks)")
        for index in 1..<opening.count {
            XCTAssertEqual(opening[index] - opening[index - 1], 3, "ticks \(opening)")
        }
        XCTAssertEqual(Array(sides.prefix(3)), [.east, .east, .east])
        XCTAssertTrue(sides.dropFirst(3).allSatisfy { $0 == .north || $0 == .south })
    }

    func testPoolLateGraceIsOneHundredFiftyMilliseconds() {
        XCTAssertEqual(Feel.lateGrace, 0.080, accuracy: 0.0001)
        XCTAssertEqual(Feel.poolLateGrace, 0.150, accuracy: 0.0001)

        let made = arrivedSwell()
        // 90 ms is past the ramp grace and still inside the pool grace.
        _ = made.tick(dt: 0.03)
        _ = made.tick(dt: 0.03)
        _ = made.tick(dt: 0.03)
        made.face(.north)
        let caught = made.tick(dt: 0.01)
        XCTAssertTrue(caught.contains { if case .caught(_, _, _, _, _, true) = $0 { return true }; return false })

        let late = arrivedSwell()
        var missed = false
        for _ in 0..<8 {
            let events = late.tick(dt: 0.03)
            if events.contains(where: { if case .missed = $0 { return true }; return false }) {
                missed = true
                break
            }
        }
        XCTAssertTrue(missed)
        XCTAssertEqual(late.lives, 2)
    }

    private func arrivedSwell() -> WavePoolSession {
        let session = WavePoolSession(seed: 3, scriptedKinds: [.swell], scriptedSides: [.north])
        session.face(.south)
        _ = run(session, until: { _ in
            session.liveWaves.contains { $0.step >= 5 && $0.side == .north }
        }, limit: 24)
        return session
    }

    func testFirstMissBreathesThreeTicksAndArmorHoldsLives() {
        let session = WavePoolSession(
            seed: 4,
            startPhase: 4,
            scriptedKinds: Array(repeating: .swell, count: 8),
            scriptedSides: Array(repeating: .north, count: 8)
        )
        session.face(.south)
        _ = run(session, until: { $0.contains { if case .missed = $0 { return true }; return false } }, limit: 30)
        XCTAssertEqual(session.lives, 2)
        XCTAssertGreaterThanOrEqual(quietSpawnSteps(session), 3)

        let armored = WavePoolSession(
            seed: 4,
            startPhase: 4,
            scriptedKinds: Array(repeating: .swell, count: 6),
            scriptedSides: Array(repeating: .north, count: 6)
        )
        armored.proofArmor = true
        armored.face(.south)
        var misses = 0
        for _ in 0..<40 where misses < 3 {
            let events = armored.tick(dt: armored.stepInterval)
            misses += events.filter { if case .missed = $0 { return true }; return false }.count
        }
        XCTAssertGreaterThanOrEqual(misses, 3)
        XCTAssertEqual(armored.lives, 3)
        XCTAssertFalse(armored.isGameOver)
        XCTAssertEqual(armored.combo, 0)
        armored.proofArmor = false
        let lost = run(armored, until: { $0.contains { if case .missed(_, _, _, true) = $0 { return true }; return false } }, limit: 20)
        XCTAssertTrue(lost.contains { if case .missed(_, _, 2, true) = $0 { return true }; return false })
        XCTAssertEqual(armored.lives, 2)
    }

    private func quietSpawnSteps(_ session: WavePoolSession) -> Int {
        var quiet = 0
        for _ in 0..<8 {
            let events = session.tick(dt: session.stepInterval)
            let spawned = events.contains { if case .spawned = $0 { return true }; return false }
            if spawned { break }
            quiet += 1
        }
        return quiet
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

import Foundation

/// The four pool walls. North is the far edge, south the near edge.
public enum Side: String, CaseIterable, Equatable, Hashable, Codable {
    case north
    case east
    case south
    case west

    public var opposite: Side {
        switch self {
        case .north: return .south
        case .south: return .north
        case .east: return .west
        case .west: return .east
        }
    }

    public var clockwise: Side {
        switch self {
        case .north: return .east
        case .east: return .south
        case .south: return .west
        case .west: return .north
        }
    }

    public var isEastWest: Bool { self == .east || self == .west }
}

public enum WaveKind: String, Equatable, Hashable, Codable {
    case swell
    case setWave
    case goldenWave
    case chop
    case lifeRing

    public var isCatchable: Bool { self != .chop }

    public var basePoints: Int {
        switch self {
        case .swell, .lifeRing: return 1
        case .setWave: return 3
        case .goldenWave: return 5
        case .chop: return 0
        }
    }
}

public enum PoolPattern: String, Equatable {
    case clockwise
    case pingPong
    case pincer
}

public struct LiveWave: Equatable {
    public let id: Int
    public let kind: WaveKind
    public let side: Side
    public let step: Int
    public let arrivalTick: Int
    public let fromPattern: Bool
}

public enum PoolEvent: Equatable {
    case whump(Side)
    case spawned(id: Int, kind: WaveKind, side: Side, arrivalTick: Int)
    case stepped(tick: Int, sides: [Side])
    case whoosh(Side, step: Int)
    case caught(id: Int, side: Side, kind: WaveKind, points: Int, combo: Int, close: Bool)
    case missed(id: Int, side: Side, lives: Int, lifeLost: Bool)
    case wiped(id: Int, side: Side, lives: Int, lifeLost: Bool)
    case dodged(id: Int, side: Side)
    case tier(String, Double)
    case spin
    case surgeWarning
    case surgeStart
    case surgeEnd
    case goldenHour
    case lifeUp
    case gameOver(score: Int, bestCombo: Int)
}

public enum PoolTables {
    /// `L` is the 0-based phase index. Phase 1 keeps two swells so the pool does not sit empty.
    public static func maxWaves(phase: Int) -> Int {
        if phase <= 1 { return 2 }
        let level = max(0, phase - 1)
        return min(4, 1 + level / 3)
    }

    /// Weights sum to 1. Pattern is 0 before phase 5, about 0.20 at phase 5, and 0.09 from phase 10.
    public static func mix(phase: Int) -> (swell: Double, set: Double, golden: Double, chop: Double, pattern: Double) {
        switch max(1, phase) {
        case 1, 2: return (1, 0, 0, 0, 0)
        case 3: return (0.82, 0.15, 0.03, 0, 0)
        case 4: return (0.70, 0.15, 0.03, 0.12, 0)
        case 5: return (0.52, 0.13, 0.03, 0.12, 0.20)
        case 6: return (0.55, 0.14, 0.03, 0.13, 0.15)
        case 7: return (0.55, 0.14, 0.03, 0.15, 0.13)
        case 8: return (0.55, 0.15, 0.03, 0.16, 0.11)
        case 9: return (0.55, 0.15, 0.03, 0.17, 0.10)
        default: return (0.55, 0.15, 0.03, 0.18, 0.09)
        }
    }
}

/// Wave-pool rules. Ramp sessions stay in `GameSession` for `-WCLegacyRamps`.
public final class WavePoolSession {
    public let seed: UInt64
    public var tuning: TuningConfig
    public var forcedPattern: PoolPattern?

    public private(set) var time: Double = 0
    public private(set) var facing: Side = .south
    public private(set) var score: Int = 0
    public private(set) var lives: Int = 3
    public private(set) var combo: Int = 0
    public private(set) var bestCombo: Int = 0
    public private(set) var phaseNumber: Int
    public private(set) var catchesInPhase: Int = 0
    public private(set) var isGameOver = false
    public private(set) var isPaused = false
    public private(set) var hitStopRemaining: Double = 0
    public private(set) var bigWavePhase: BigWavePhase = .idle
    public private(set) var goldenHourRemaining: Double = 0
    public private(set) var lifePips: Int = 0
    public private(set) var globalStep: Int = 0
    public private(set) var spinSerial: Int = 0
    public private(set) var rideUntil: Double = 0
    public private(set) var wipeUntil: Double = 0
    public private(set) var mercyCatchesRemaining: Int = 0
    /// Debug proof runs ignore life-loss until the test turns this off. Release leaves it false.
    public var proofArmor = false

    public var multiplier: Double { ScoreMath.comboMultiplier(for: combo) }
    public var stepInterval: Double { currentInterval() }
    public var phaseIndex: Int { max(0, phaseNumber - 1) }

    public var liveWaves: [LiveWave] {
        waves.filter { !$0.resolved }.map { wave in
            LiveWave(
                id: wave.id,
                kind: wave.kind,
                side: wave.side,
                step: wave.step,
                arrivalTick: wave.arrivalTick,
                fromPattern: wave.fromPattern
            )
        }
    }

    public var blinkingVents: Set<Side> {
        if bigWavePhase == .warning { return Set(Side.allCases) }
        if let side = telegraphSide { return [side] }
        return []
    }

    public var ringSides: Set<Side> {
        Set(waves.filter { !$0.resolved && $0.step >= 4 }.map(\.side))
    }

    public init(
        seed: UInt64,
        tuning: TuningConfig = TuningConfig(),
        startPhase: Int = 1,
        scriptedKinds: [WaveKind] = [],
        scriptedSides: [Side] = [],
        forcedPattern: PoolPattern? = nil
    ) {
        self.seed = seed
        self.tuning = tuning
        self.phaseNumber = max(1, startPhase)
        self.rng = SeededRNG(seed: seed)
        self.kindQueue = scriptedKinds
        self.sideQueue = scriptedSides
        self.forcedPattern = forcedPattern
        self.nextStepTime = 0
        self.spawnOnTick = 2
        // First vent blink is on tick 1, inside the first half-second, not after a full step.
        // Phase 1 uses the slower tutorial clock; later phases use SpeedCurve.
        let opening = self.phaseNumber <= 1
            ? 0.75
            : SpeedCurve.stepInterval(level: max(0, self.phaseNumber - 1))
        let scaled = opening / max(0.5, min(2, tuning.speedMultiplier))
        self.nextStepTime = min(0.45, scaled)
    }

    public func setPaused(_ paused: Bool) {
        guard !isGameOver else { return }
        isPaused = paused
    }

    /// Instant. Newest call wins. The pose tween is the app's problem.
    public func face(_ side: Side) {
        guard !isGameOver, !isPaused else { return }
        facing = side
    }

    /// The catchable that arrives soonest, skipping a side that also has a chop due then.
    public func suggestedSide() -> Side? {
        let live = liveWaves
        let catchables = live.filter { $0.kind.isCatchable }.sorted { $0.arrivalTick < $1.arrivalTick }
        for catchable in catchables {
            let blocked = live.contains {
                $0.kind == .chop && $0.side == catchable.side && $0.arrivalTick == catchable.arrivalTick
            }
            if !blocked { return catchable.side }
        }
        return catchables.first?.side
    }

    @discardableResult
    public func tick(dt: Double) -> [PoolEvent] {
        guard !isGameOver, !isPaused else { return [] }
        guard dt >= 0 else { return [] }
        var events = resolveArrivals()
        if hitStopRemaining > 0 {
            let used = min(dt, hitStopRemaining)
            hitStopRemaining -= used
            let rest = dt - used
            if rest > 0 { events += advance(by: rest) }
            return events
        }
        if dt == 0 { return events }
        events += advance(by: dt)
        return events
    }

    // MARK: - Clock

    private struct ActiveWave {
        var id: Int
        var kind: WaveKind
        var side: Side
        var step: Int
        var arrivalTick: Int
        var graceDeadline: Double?
        var resolved = false
        var fromPattern = false
    }

    private var rng: SeededRNG
    private var waves: [ActiveWave] = []
    private var nextID = 1
    private var nextStepTime: Double
    private var spawnOnTick: Int
    private var telegraphSide: Side?
    private var telegraphKind: WaveKind?
    private var telegraphPattern = false
    private var kindQueue: [WaveKind]
    private var sideQueue: [Side]
    private var patternQueue: [(Side, WaveKind)] = []
    private var mercySkip = 0
    private var mercyChopBlock = 0
    private var lastCatchTick: [Side: Int] = [:]
    private var lastCatchableArrivalTick = -10
    private var lastCatchableSide: Side?
    private var spawnCount = 0
    private var surgeCursor: Side = .north
    private var surgeEndsAt = 0.0
    private var warningEndsAt = 0.0
    private var breatherEndsAt = 0.0
    private var didSpotlightSurge = false
    private var sawGoldenHour = false
    private var lifeLosses = 0

    private func currentInterval() -> Double {
        var level = phaseIndex
        if mercyCatchesRemaining > 0 { level = max(0, level - 1) }
        if bigWavePhase == .breather { level = max(0, level - 1) }
        // Phase 1 is a fixed 0.75s tutorial step. Phase 2 onward keeps the ramp curve,
        // including the mercy and breather drop of one level.
        var interval = phaseNumber <= 1 ? 0.75 : SpeedCurve.stepInterval(level: level)
        if bigWavePhase == .active { interval *= Feel.bigWaveStepScale }
        return interval / tuning.clamped().speedMultiplier
    }

    /// Phase 1 commits a swell every third tick. Later phases telegraph on the next tick.
    private func spawnGap() -> Int {
        phaseNumber <= 1 ? 3 : 1
    }

    private func advance(by dt: Double) -> [PoolEvent] {
        if goldenHourRemaining > 0 {
            goldenHourRemaining = max(0, goldenHourRemaining - dt)
        }
        time += dt
        var events = updateSurgeClock()
        guard time + 0.000001 >= nextStepTime else { return events }
        nextStepTime += currentInterval()
        events += stepOnce()
        return events
    }

    private func stepOnce() -> [PoolEvent] {
        globalStep += 1
        if mercySkip > 0 { mercySkip -= 1 }
        var events: [PoolEvent] = []
        var moved: [Side] = []
        for index in waves.indices where !waves[index].resolved && waves[index].step < 5 {
            waves[index].step += 1
            moved.append(waves[index].side)
            events.append(.whoosh(waves[index].side, step: waves[index].step))
        }
        if !moved.isEmpty {
            events.append(.stepped(tick: globalStep, sides: Array(Set(moved))))
        }
        events += resolveArrivals()
        events += updateSurgeClock()
        let gap = spawnGap()
        if globalStep == spawnOnTick, let side = telegraphSide, let kind = telegraphKind {
            events += commitSpawn(side: side, kind: kind, fromPattern: telegraphPattern)
            telegraphSide = nil
            telegraphKind = nil
            telegraphPattern = false
            spawnOnTick = globalStep + gap
        }
        if telegraphSide == nil {
            if let plan = planSpawn() {
                if spawnOnTick <= globalStep {
                    events += commitSpawn(side: plan.side, kind: plan.kind, fromPattern: plan.pattern)
                    spawnOnTick = globalStep + gap
                } else if spawnOnTick == globalStep + 1 {
                    telegraphSide = plan.side
                    telegraphKind = plan.kind
                    telegraphPattern = plan.pattern
                    events.append(.whump(plan.side))
                }
            } else if spawnOnTick <= globalStep + 1 {
                spawnOnTick = globalStep + (phaseNumber <= 1 ? 3 : 2)
            }
        }
        return events
    }

    private func updateSurgeClock() -> [PoolEvent] {
        var events: [PoolEvent] = []
        if bigWavePhase == .warning && time >= warningEndsAt {
            bigWavePhase = .active
            surgeEndsAt = time + tuning.clamped().bigWaveDuration
            surgeCursor = .north
            events.append(.surgeStart)
        } else if bigWavePhase == .active && time >= surgeEndsAt {
            bigWavePhase = .breather
            breatherEndsAt = time + Feel.bigWaveBreather
            events.append(.surgeEnd)
        } else if bigWavePhase == .breather && time >= breatherEndsAt {
            bigWavePhase = .idle
        }
        return events
    }

    // MARK: - Spawns

    private struct Plan {
        var side: Side
        var kind: WaveKind
        var pattern: Bool
    }

    private func planSpawn() -> Plan? {
        guard mercySkip == 0 else { return nil }
        guard bigWavePhase != .warning, bigWavePhase != .breather else { return nil }
        let cap = patternQueue.isEmpty && forcedPattern == nil
            ? PoolTables.maxWaves(phase: phaseNumber)
            : 4
        if waves.contains(where: { !$0.resolved }) && liveCount >= cap && bigWavePhase != .active {
            return nil
        }
        if bigWavePhase == .active {
            if liveCount >= 4 { return nil }
            let side = surgeCursor
            surgeCursor = side.clockwise
            return Plan(side: side, kind: .swell, pattern: false)
        }
        if patternQueue.isEmpty, let pattern = takePattern() {
            patternQueue = pattern
        }
        if !patternQueue.isEmpty {
            let next = patternQueue[0]
            guard sideLegal(next.0, kind: next.1, spawnTick: spawnOnTick) else { return nil }
            patternQueue.removeFirst()
            return Plan(side: next.0, kind: next.1, pattern: true)
        }
        let kind = takeKind(spawnTick: spawnOnTick)
        guard let side = takeSide(kind: kind, spawnTick: spawnOnTick) else { return nil }
        return Plan(side: side, kind: kind, pattern: false)
    }

    private var liveCount: Int { waves.filter { !$0.resolved }.count }

    private func takePattern() -> [(Side, WaveKind)]? {
        if let forced = forcedPattern, phaseNumber >= 5 {
            forcedPattern = nil
            return expand(forced)
        }
        guard kindQueue.isEmpty, sideQueue.isEmpty else { return nil }
        let chance = PoolTables.mix(phase: phaseNumber).pattern
        guard chance > 0, rng.nextUnit() < chance else { return nil }
        var options: [PoolPattern] = [.clockwise]
        if phaseNumber >= 6 { options += [.pingPong, .pincer] }
        return expand(options[rng.nextInt(options.count)])
    }

    private func expand(_ pattern: PoolPattern) -> [(Side, WaveKind)] {
        switch pattern {
        case .clockwise:
            let start = Side.allCases[rng.nextInt(Side.allCases.count)]
            var side = start
            return (0..<4).map { _ in
                let item = (side, WaveKind.swell)
                side = side.clockwise
                return item
            }
        case .pingPong:
            return [(.east, .swell), (.west, .swell), (.east, .swell)]
        case .pincer:
            return [(.north, .swell), (.south, .swell)]
        }
    }

    private func takeKind(spawnTick: Int) -> WaveKind {
        if !kindQueue.isEmpty {
            let kind = kindQueue.removeFirst()
            if kind == .chop && (mercyChopBlock > 0 || blockedChop(arrival: spawnTick + 4)) {
                return .swell
            }
            return kind
        }
        if tuning.spotlightGoldenWave && spawnCount == 1 && !waves.contains(where: { !$0.resolved && $0.kind == .goldenWave }) {
            return .goldenWave
        }
        let mix = PoolTables.mix(phase: phaseNumber)
        var swell = mix.swell
        let set = mix.set
        var golden = mix.golden
        var chop = mix.chop
        let pattern = mix.pattern
        swell += pattern
        if mercyChopBlock > 0 || chopBlockedBySchedule(spawnTick: spawnTick) || chopCount >= 2 {
            swell += chop
            chop = 0
        }
        if waves.contains(where: { !$0.resolved && $0.kind == .goldenWave }) {
            swell += golden
            golden = 0
        }
        let roll = rng.nextUnit() * (swell + set + golden + chop)
        var cursor = swell
        if roll < cursor { return maybeLifeRing(.swell) }
        cursor += set
        if roll < cursor { return .setWave }
        cursor += golden
        if roll < cursor { return .goldenWave }
        return .chop
    }

    private func maybeLifeRing(_ kind: WaveKind) -> WaveKind {
        guard kind == .swell, phaseNumber >= 3, rng.nextUnit() < 0.12 else { return kind }
        return .lifeRing
    }

    private var chopCount: Int { waves.filter { !$0.resolved && $0.kind == .chop }.count }

    private func chopBlockedBySchedule(spawnTick: Int) -> Bool {
        blockedChop(arrival: spawnTick + 4)
    }

    private func blockedChop(arrival: Int) -> Bool {
        waves.contains { !$0.resolved && $0.kind.isCatchable && $0.arrivalTick == arrival }
    }

    private func takeSide(kind: WaveKind, spawnTick: Int) -> Side? {
        if !sideQueue.isEmpty {
            let side = sideQueue[0]
            guard sideLegal(side, kind: kind, spawnTick: spawnTick) else { return nil }
            sideQueue.removeFirst()
            return side
        }
        // The first three swells of a run come from the wall the surfer is facing,
        // including east and west, so a turn during the tutorial still gets a wave.
        if phaseNumber <= 1 && spawnCount < 3 {
            guard sideLegal(facing, kind: kind, spawnTick: spawnTick, ignorePhaseLimit: true) else { return nil }
            return facing
        }
        var options = legalSides(kind: kind, spawnTick: spawnTick)
        if options.isEmpty { return nil }
        rng.shuffle(&options)
        return options[0]
    }

    private func legalSides(kind: WaveKind, spawnTick: Int) -> [Side] {
        allowedSides().filter { sideLegal($0, kind: kind, spawnTick: spawnTick) }
    }

    private func allowedSides() -> [Side] {
        if bigWavePhase == .active { return Side.allCases }
        if phaseNumber <= 1 { return [.north, .south] }
        return Side.allCases
    }

    private func sideLegal(_ side: Side, kind: WaveKind, spawnTick: Int, ignorePhaseLimit: Bool = false) -> Bool {
        if !ignorePhaseLimit && !allowedSides().contains(side) { return false }
        // A new crest at row 1 must be more than one row away from a crest already on this wall.
        if waves.contains(where: { !$0.resolved && $0.side == side && $0.step <= 2 }) {
            return false
        }
        let arrival = spawnTick + 4
        if kind.isCatchable {
            let gap = phaseNumber >= 5 ? Feel.relaxedTickGap : Feel.catchableTickGap
            if lastCatchableArrivalTick >= 0 && arrival - lastCatchableArrivalTick < gap {
                return false
            }
            if phaseNumber < 6, let previous = lastCatchableSide, previous.opposite == side,
               arrival == lastCatchableArrivalTick + 1 {
                return false
            }
            if waves.contains(where: { !$0.resolved && $0.kind == .chop && $0.arrivalTick == arrival && $0.side == side }) {
                return false
            }
        } else if blockedChop(arrival: arrival) {
            return false
        }
        return true
    }

    private func commitSpawn(side: Side, kind: WaveKind, fromPattern: Bool) -> [PoolEvent] {
        if mercyChopBlock > 0 { mercyChopBlock -= 1 }
        let arrival = globalStep + 4
        let wave = ActiveWave(
            id: nextID,
            kind: kind,
            side: side,
            step: 1,
            arrivalTick: arrival,
            fromPattern: fromPattern
        )
        nextID += 1
        waves.append(wave)
        spawnCount += 1
        if kind.isCatchable {
            lastCatchableArrivalTick = arrival
            lastCatchableSide = side
        }
        return [
            .whoosh(side, step: 1),
            .spawned(id: wave.id, kind: kind, side: side, arrivalTick: arrival),
        ]
    }

    // MARK: - Resolution

    private func resolveArrivals() -> [PoolEvent] {
        var events: [PoolEvent] = []
        for index in waves.indices {
            guard !waves[index].resolved, waves[index].step >= 5 else { continue }
            let wave = waves[index]
            let facingIt = facing == wave.side
            if wave.kind == .chop {
                if facingIt {
                    events += wipe(index)
                } else {
                    events += dodge(index)
                }
                continue
            }
            if facingIt {
                events += collect(index, close: wave.graceDeadline != nil)
            } else if let deadline = wave.graceDeadline {
                if time >= deadline { events += miss(index) }
            } else {
                waves[index].graceDeadline = time + Feel.poolLateGrace
            }
        }
        return events
    }

    private func collect(_ index: Int, close: Bool) -> [PoolEvent] {
        let wave = waves[index]
        waves[index].resolved = true
        combo += 1
        if combo > bestCombo { bestCombo = combo }
        if mercyCatchesRemaining > 0 { mercyCatchesRemaining -= 1 }
        var base = wave.kind.basePoints
        if bigWavePhase == .active { base += 2 }
        var points = ScoreMath.points(base: base, multiplier: multiplier)
        if goldenHourRemaining > 0 { points *= 2 }
        score += points
        rideUntil = time + 0.150
        var events: [PoolEvent] = [
            .caught(id: wave.id, side: wave.side, kind: wave.kind, points: points, combo: combo, close: close),
        ]
        if let name = ScoreMath.callout(for: combo) {
            events.append(.tier(name, multiplier))
        }
        lastCatchTick[wave.side] = globalStep
        if Side.allCases.allSatisfy({ side in
            guard let tick = lastCatchTick[side] else { return false }
            return globalStep - tick <= 6
        }) {
            score += 5
            spinSerial += 1
            lastCatchTick.removeAll()
            events.append(.spin)
        }
        if wave.kind == .lifeRing {
            lifePips += 1
            if lifePips >= 3 {
                lifePips = 0
                if lives < 3 {
                    lives += 1
                    events.append(.lifeUp)
                }
            }
        }
        if wave.kind == .goldenWave {
            goldenHourRemaining = 3
            if !sawGoldenHour {
                sawGoldenHour = true
                events.append(.goldenHour)
            }
        }
        catchesInPhase += 1
        events += clearPhaseIfNeeded()
        if tuning.spotlightSurge && !didSpotlightSurge && combo >= 5 && bigWavePhase == .idle {
            events += startSurge()
        }
        hitStopRemaining = Feel.hitStopCatch
        return events
    }

    private func miss(_ index: Int) -> [PoolEvent] {
        let wave = waves[index]
        waves[index].resolved = true
        return punish(wave: wave, wipeout: false)
    }

    private func wipe(_ index: Int) -> [PoolEvent] {
        let wave = waves[index]
        waves[index].resolved = true
        wipeUntil = time + 0.30
        return punish(wave: wave, wipeout: true)
    }

    private func punish(wave: ActiveWave, wipeout: Bool) -> [PoolEvent] {
        let surge = bigWavePhase == .active
        var lifeLost = false
        if !surge && proofArmor {
            lifeLost = false
        } else if !surge {
            combo = 0
            lives -= 1
            lifeLost = true
            wipeUntil = time + 0.45
            lifeLosses += 1
            // The first life of a run is a longer breather. Later misses stay on the short skip.
            mercySkip = lifeLosses == 1 ? 3 : Feel.mercySkipTicks
            mercyCatchesRemaining = Feel.mercyCatches
            mercyChopBlock = Feel.mercyClearSpawns
            lastCatchTick.removeAll()
        }
        hitStopRemaining = wipeout ? Feel.hitStopSting : Feel.hitStopMiss
        var events: [PoolEvent] = []
        if wipeout {
            events.append(.wiped(id: wave.id, side: wave.side, lives: lives, lifeLost: lifeLost))
        } else {
            events.append(.missed(id: wave.id, side: wave.side, lives: lives, lifeLost: lifeLost))
        }
        if lives <= 0 {
            isGameOver = true
            events.append(.gameOver(score: score, bestCombo: bestCombo))
        }
        return events
    }

    private func dodge(_ index: Int) -> [PoolEvent] {
        let wave = waves[index]
        waves[index].resolved = true
        return [.dodged(id: wave.id, side: wave.side)]
    }

    private func clearPhaseIfNeeded() -> [PoolEvent] {
        let target = PhaseTable.clearTarget(phaseNumber: phaseNumber)
        guard catchesInPhase >= target else { return [] }
        let cleared = phaseNumber
        catchesInPhase = 0
        phaseNumber += 1
        guard tuning.bigWavesEnabled, PhaseTable.bigWaveFollowsClear(of: cleared), bigWavePhase == .idle else {
            return []
        }
        return startSurge()
    }

    private func startSurge() -> [PoolEvent] {
        guard bigWavePhase == .idle else { return [] }
        didSpotlightSurge = true
        bigWavePhase = .warning
        warningEndsAt = time + Feel.bigWaveWarning
        patternQueue.removeAll()
        telegraphSide = nil
        telegraphKind = nil
        return [.surgeWarning]
    }
}

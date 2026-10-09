import Foundation

/// Deterministic simulation. Call `setPosition` when input arrives, then `tick(dt)`.
/// A position change is instant. `tick` applies that position before it resolves arrivals.
public final class GameSession {
    public let seed: UInt64
    public var tuning: TuningConfig

    public private(set) var time: Double = 0
    public private(set) var position: Lane = .lowerLeft
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
    public private(set) var bigWaveBonusActive = false
    public private(set) var mercyCatchesRemaining: Int = 0
    public private(set) var mercyJellyBlock: Int = 0
    public private(set) var stalled = false

    public var phaseIndex: Int { max(0, phaseNumber - 1) }

    /// Phase index after mercy and the Big Wave breather. Travel time uses this.
    public var speedLevel: Int { levelForSpeed() }

    public var multiplier: Double { currentMultiplier() }

    public var liveObjects: [LiveObject] {
        objects.filter { !$0.resolved }.map { object in
            let wobbling: Bool
            if case .grace = object.state { wobbling = true } else { wobbling = false }
            let progress: Double
            if wobbling || time >= object.arrivalTime {
                progress = 1
            } else {
                progress = Motion.visualProgress(
                    kind: object.kind,
                    spawnTime: object.spawnTime,
                    arrivalTime: object.arrivalTime,
                    now: time,
                    hopSalt: object.hopSalt
                )
            }
            return LiveObject(
                id: object.id,
                kind: object.kind,
                lane: object.lane,
                arrivalTime: object.arrivalTime,
                travel: object.travel,
                progress: progress,
                wobbling: wobbling,
                telegraph: object.telegraphed,
                hopSalt: object.hopSalt
            )
        }
    }

    /// Lane the player should stand in to meet the next catchable, avoiding a jellyfish on that spot.
    public func suggestedLane() -> Lane? {
        let live = liveObjects
        let catchables = live.filter { $0.kind.isCatchable }.sorted { $0.arrivalTime < $1.arrivalTime }
        let jellies = live.filter { $0.kind == .jellyfish }
        for catchable in catchables {
            let blocked = jellies.contains {
                $0.lane == catchable.lane && abs($0.arrivalTime - catchable.arrivalTime) < 0.45
            }
            if !blocked { return catchable.lane }
        }
        return catchables.first?.lane
    }

    public init(seed: UInt64, tuning: TuningConfig = TuningConfig(), startPhase: Int = 1) {
        self.seed = seed
        self.tuning = tuning
        self.rng = SeededRNG(seed: seed)
        self.phaseNumber = max(1, startPhase)
        self.nextSpawnTime = 0
    }

    public func setPaused(_ paused: Bool) {
        guard !isGameOver else { return }
        isPaused = paused
    }

    public func setPosition(_ lane: Lane) {
        guard !isGameOver, !isPaused else { return }
        guard lane != position else { return }
        lastLeft[position] = time
        position = lane
    }

    @discardableResult
    public func tick(dt: Double) -> [GameEvent] {
        guard !isGameOver, !isPaused else { return [] }
        guard dt >= 0 else { return [] }

        if hitStopRemaining > 0 {
            let events = resolveInputWindows()
            hitStopRemaining = max(0, hitStopRemaining - dt)
            return events
        }

        var events = resolveInputWindows()
        if dt == 0 { return events }
        events += advance(by: dt)
        return events
    }

    // MARK: - Simulation

    private struct ActiveObject {
        var id: Int
        var kind: ObjectKind
        var lane: Lane
        var spawnTime: Double
        var arrivalTime: Double
        var travel: Double
        var hopSalt: UInt64
        var state: FlightState
        var telegraphed: Bool
        var resolved: Bool
    }

    private enum FlightState {
        case flying
        case grace(until: Double)
        case stingWindow(until: Double)
    }

    private enum WaveClock {
        case none
        case warning(end: Double)
        case active(end: Double)
        case breather(end: Double)
    }

    private var rng: SeededRNG
    private var objects: [ActiveObject] = []
    private var nextID = 1
    private var nextSpawnTime: Double
    private var waveClock: WaveClock = .none
    private var waveQueued = false
    private var mercyUntil: Double = 0
    private var lastLeft: [Lane: Double] = [:]
    private var catchableLaneHistory: [Lane] = []
    private var scriptIndex = 0
    private var successfulSpawns = 0
    private var usingScriptPeek = false

    private func advance(by dt: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        let target = time + dt
        var safety = 0
        var repeats = 0
        var previousMark = -1.0

        while !isGameOver && time < target - 1e-9 {
            safety += 1
            if safety > 20000 {
                stalled = true
                break
            }
            guard let instant = nextInstant(upTo: target) else {
                time = target
                break
            }
            if instant > target + 1e-9 {
                time = target
                break
            }
            if abs(instant - previousMark) < 1e-12 && abs(instant - time) < 1e-9 {
                repeats += 1
                if repeats > 4 {
                    stalled = true
                    time = min(target, time + 0.001)
                    repeats = 0
                    continue
                }
            } else {
                repeats = 0
            }
            previousMark = instant
            if instant > time {
                time = instant
            }
            let stopBefore = hitStopRemaining
            events += processInstant()
            if isGameOver || hitStopRemaining > stopBefore {
                break
            }
        }
        return events
    }

    private func nextInstant(upTo limit: Double) -> Double? {
        var best: Double?
        func consider(_ raw: Double) {
            let when = raw < time ? time : raw
            if when > limit + 1e-8 { return }
            if best == nil || when < best! {
                best = when
            }
        }

        consider(nextSpawnTime)
        if let transition = waveTransitionTime() {
            consider(transition)
        }
        for object in objects where !object.resolved {
            if !object.telegraphed {
                consider(object.arrivalTime - SpeedCurve.telegraphLead(travel: object.travel))
            }
            switch object.state {
            case .flying:
                consider(object.arrivalTime)
            case .grace(let until), .stingWindow(let until):
                consider(until)
            }
        }
        return best
    }

    private func waveTransitionTime() -> Double? {
        switch waveClock {
        case .none:
            return nil
        case .warning(let end), .active(let end), .breather(let end):
            return end
        }
    }

    private func processInstant() -> [GameEvent] {
        var events: [GameEvent] = []
        events += fireTelegraphs()
        events += fireArrivals()
        events += fireDeadlines()
        purge()
        if isGameOver { return events }
        events += transitionWave()
        syncWavePhase()
        events += attemptSpawn()
        purge()
        return events
    }

    private func due(_ stamp: Double) -> Bool {
        stamp <= time + 1e-8
    }

    private func fireTelegraphs() -> [GameEvent] {
        var events: [GameEvent] = []
        for index in objects.indices {
            if objects[index].resolved || objects[index].telegraphed { continue }
            let lead = SpeedCurve.telegraphLead(travel: objects[index].travel)
            if due(objects[index].arrivalTime - lead) {
                objects[index].telegraphed = true
                events.append(.telegraph(
                    id: objects[index].id,
                    lane: objects[index].lane,
                    kind: objects[index].kind
                ))
            }
        }
        return events
    }

    private func fireArrivals() -> [GameEvent] {
        var events: [GameEvent] = []
        let dueIndexes = objects.indices.filter { index in
            !objects[index].resolved && isFlying(objects[index]) && due(objects[index].arrivalTime)
        }
        let ordered = dueIndexes.sorted { lhs, rhs in
            let leftCatchable = objects[lhs].kind.isCatchable
            let rightCatchable = objects[rhs].kind.isCatchable
            if leftCatchable != rightCatchable { return leftCatchable && !rightCatchable }
            return objects[lhs].arrivalTime < objects[rhs].arrivalTime
        }
        for index in ordered {
            if objects[index].resolved { continue }
            events += arrive(index)
            if isGameOver { break }
        }
        return events
    }

    private func fireDeadlines() -> [GameEvent] {
        var events: [GameEvent] = []
        for index in objects.indices {
            if objects[index].resolved { continue }
            switch objects[index].state {
            case .grace(let until) where due(until):
                if position == objects[index].lane {
                    events += catchObject(index, close: true)
                } else {
                    events += missObject(index)
                }
            case .stingWindow(let until) where due(until):
                if position == objects[index].lane {
                    events += stingObject(index)
                } else {
                    events += dodgeObject(index)
                }
            default:
                break
            }
            if isGameOver { break }
        }
        return events
    }

    private func arrive(_ index: Int) -> [GameEvent] {
        if objects[index].kind == .jellyfish {
            if position == objects[index].lane {
                let until = objects[index].arrivalTime + Feel.stingConfirm
                objects[index].state = .stingWindow(until: until)
                return []
            }
            if let leftAt = lastLeft[objects[index].lane], time - leftAt <= Feel.dodgeMemory + 1e-9 {
                return dodgeObject(index)
            }
            return passObject(index)
        }
        if position == objects[index].lane {
            return catchObject(index, close: false)
        }
        let until = objects[index].arrivalTime + Feel.lateGrace
        objects[index].state = .grace(until: until)
        return []
    }

    private func resolveInputWindows() -> [GameEvent] {
        var events: [GameEvent] = []
        for index in objects.indices {
            if objects[index].resolved { continue }
            switch objects[index].state {
            case .grace(let until):
                if position == objects[index].lane && time <= until + 1e-9 {
                    events += catchObject(index, close: true)
                }
            case .stingWindow(let until):
                if position != objects[index].lane && time < until - 1e-9 {
                    events += dodgeObject(index)
                }
            case .flying:
                break
            }
            if isGameOver { break }
        }
        purge()
        return events
    }

    private func catchObject(_ index: Int, close: Bool) -> [GameEvent] {
        objects[index].resolved = true
        combo += 1
        if combo > bestCombo { bestCombo = combo }
        if mercyCatchesRemaining > 0 { mercyCatchesRemaining -= 1 }
        catchesInPhase += 1
        let mult = currentMultiplier()
        let awarded = ScoreMath.points(base: objects[index].kind.basePoints, multiplier: mult)
        score += awarded
        var events: [GameEvent] = [
            .caught(
                id: objects[index].id,
                lane: objects[index].lane,
                kind: objects[index].kind,
                points: awarded,
                combo: combo,
                close: close
            ),
            .comboChanged(combo: combo, multiplier: mult),
        ]
        events += maybeAdvancePhase()
        return events
    }

    private func missObject(_ index: Int) -> [GameEvent] {
        let id = objects[index].id
        let lane = objects[index].lane
        objects[index].resolved = true
        if isWaveActive {
            var events: [GameEvent] = [.missed(id: id, lane: lane, lives: lives, lifeLost: false)]
            if bigWaveBonusActive {
                bigWaveBonusActive = false
                events.append(.bigWaveBonusLost)
            }
            return events
        }
        return loseLife(primary: .missed(id: id, lane: lane, lives: lives - 1, lifeLost: true), hitStop: Feel.hitStopMiss)
    }

    private func stingObject(_ index: Int) -> [GameEvent] {
        let id = objects[index].id
        let lane = objects[index].lane
        objects[index].resolved = true
        return loseLife(primary: .stung(id: id, lane: lane, lives: lives - 1), hitStop: Feel.hitStopSting)
    }

    private func loseLife(primary: GameEvent, hitStop: Double) -> [GameEvent] {
        lives -= 1
        let previousCombo = combo
        combo = 0
        mercyUntil = time + Feel.mercySilence
        nextSpawnTime = max(nextSpawnTime, mercyUntil)
        mercyCatchesRemaining = Feel.mercyCatches
        mercyJellyBlock = Feel.mercyClearSpawns
        var events: [GameEvent] = [rewriteLives(primary)]
        if previousCombo != 0 {
            events.append(.comboChanged(combo: 0, multiplier: currentMultiplier()))
        }
        events += fadeImminentJellyfish()
        hitStopRemaining = hitStop
        if lives <= 0 {
            lives = 0
            isGameOver = true
            events[0] = rewriteLives(primary, lives: 0)
            events.append(.gameOver(score: score, bestCombo: bestCombo))
        }
        return events
    }

    private func rewriteLives(_ event: GameEvent, lives override: Int? = nil) -> GameEvent {
        let value = override ?? lives
        switch event {
        case .missed(let id, let lane, _, let lifeLost):
            return .missed(id: id, lane: lane, lives: value, lifeLost: lifeLost)
        case .stung(let id, let lane, _):
            return .stung(id: id, lane: lane, lives: value)
        default:
            return event
        }
    }

    private func fadeImminentJellyfish() -> [GameEvent] {
        var events: [GameEvent] = []
        for index in objects.indices {
            let object = objects[index]
            guard !object.resolved, object.kind == .jellyfish else { continue }
            guard isFlying(object) else { continue }
            guard object.arrivalTime > time - 1e-9, object.arrivalTime <= time + Feel.mercySilence + 1e-9 else { continue }
            objects[index].resolved = true
            events.append(.jellyfishFaded(id: object.id, lane: object.lane))
        }
        return events
    }

    private func passObject(_ index: Int) -> [GameEvent] {
        let event = GameEvent.jellyfishPassed(id: objects[index].id, lane: objects[index].lane)
        objects[index].resolved = true
        return [event]
    }

    private func dodgeObject(_ index: Int) -> [GameEvent] {
        let event = GameEvent.dodged(id: objects[index].id, lane: objects[index].lane)
        objects[index].resolved = true
        return [event]
    }

    private func maybeAdvancePhase() -> [GameEvent] {
        let target = PhaseTable.clearTarget(phaseNumber: phaseNumber)
        guard catchesInPhase >= target else { return [] }
        let cleared = phaseNumber
        catchesInPhase = 0
        phaseNumber += 1
        guard tuning.bigWavesEnabled, PhaseTable.bigWaveFollowsClear(of: cleared) else { return [] }
        return beginWarning()
    }

    private func beginWarning() -> [GameEvent] {
        switch waveClock {
        case .none:
            waveClock = .warning(end: time + Feel.bigWaveWarning)
            syncWavePhase()
            return [.bigWaveWarning]
        default:
            waveQueued = true
            return []
        }
    }

    private func transitionWave() -> [GameEvent] {
        switch waveClock {
        case .warning(let end) where due(end):
            bigWaveBonusActive = true
            waveClock = .active(end: time + tuning.clamped().bigWaveDuration)
            return [.bigWaveStart]
        case .active(let end) where due(end):
            bigWaveBonusActive = false
            waveClock = .breather(end: time + Feel.bigWaveBreather)
            return [.bigWaveEnd]
        case .breather(let end) where due(end):
            waveClock = .none
            if waveQueued {
                waveQueued = false
                return beginWarning()
            }
            return []
        default:
            return []
        }
    }

    private func syncWavePhase() {
        switch waveClock {
        case .none: bigWavePhase = .idle
        case .warning: bigWavePhase = .warning
        case .active: bigWavePhase = .active
        case .breather: bigWavePhase = .breather
        }
    }

    private var isWaveActive: Bool {
        if case .active = waveClock { return true }
        return false
    }

    private var isBreather: Bool {
        if case .breather = waveClock { return true }
        return false
    }

    private func attemptSpawn() -> [GameEvent] {
        guard due(nextSpawnTime) else { return [] }

        if time < mercyUntil - 1e-8 {
            nextSpawnTime = mercyUntil
            return []
        }
        if case .warning(let end) = waveClock, time < end - 1e-8 {
            nextSpawnTime = end
            return []
        }

        let level = levelForSpeed()
        let cap = SpeedCurve.maxOnScreen(level: level)
        if objects.contains(where: { !$0.resolved }) && unresolvedCount() >= cap {
            nextSpawnTime = time + 0.05
            return []
        }

        let kind = peekKind()
        let travel = SpeedCurve.travelTime(level: level, kind: kind, tuning: tuning)
        let arrival = time + travel
        guard let lane = chooseLane(kind: kind, arrival: arrival) else {
            nextSpawnTime = time + 0.05
            usingScriptPeek = false
            return []
        }

        commitKindPeek()
        if kind.isCatchable && mercyJellyBlock > 0 {
            mercyJellyBlock -= 1
        }
        if kind.isCatchable {
            catchableLaneHistory.append(lane)
            if catchableLaneHistory.count > 32 {
                catchableLaneHistory.removeFirst(catchableLaneHistory.count - 32)
            }
        }

        let id = nextID
        nextID += 1
        let salt = rng.nextUInt64()
        var spawned = ActiveObject(
            id: id,
            kind: kind,
            lane: lane,
            spawnTime: time,
            arrivalTime: arrival,
            travel: travel,
            hopSalt: salt,
            state: .flying,
            telegraphed: false,
            resolved: false
        )
        var events: [GameEvent] = []
        let lead = SpeedCurve.telegraphLead(travel: travel)
        if due(arrival - lead) {
            spawned.telegraphed = true
            events.append(.telegraph(id: id, lane: lane, kind: kind))
        }
        objects.append(spawned)
        events.append(.spawned(id: id, kind: kind, lane: lane, arrival: arrival, travel: travel))
        successfulSpawns += 1
        let interval = SpeedCurve.spawnInterval(level: level, tuning: tuning, bigWave: isWaveActive)
        nextSpawnTime = time + interval
        return events
    }

    private func unresolvedCount() -> Int {
        objects.reduce(0) { $0 + ($1.resolved ? 0 : 1) }
    }

    private func peekKind() -> ObjectKind {
        usingScriptPeek = false
        let blocked = mercyJellyBlock > 0 || isBreather || isWaveActive
        if tuning.demoSpotlightJellyfish && successfulSpawns == 2 && !blocked {
            return .jellyfish
        }
        if scriptIndex < tuning.scriptedKinds.count {
            usingScriptPeek = true
            var kind = tuning.scriptedKinds[scriptIndex]
            if blocked && kind == .jellyfish {
                kind = .shell
            }
            return kind
        }
        return rollKind(blockJellyfish: blocked)
    }

    private func commitKindPeek() {
        if usingScriptPeek {
            scriptIndex += 1
        }
        usingScriptPeek = false
    }

    private func rollKind(blockJellyfish: Bool) -> ObjectKind {
        var mix = PhaseTable.mix(phaseNumber: phaseNumber)
        if isWaveActive {
            mix = (60, 30, 10, 0)
        }
        if blockJellyfish || isBreather {
            mix.jellyfish = 0
        } else {
            mix.jellyfish *= tuning.clamped().jellyfishMultiplier
        }
        let total = mix.shell + mix.board + mix.ring + mix.jellyfish
        if total <= 0 { return .shell }
        var roll = rng.nextUnit() * total
        if roll < mix.shell { return .shell }
        roll -= mix.shell
        if roll < mix.board { return .board }
        roll -= mix.board
        if roll < mix.ring { return .lifeRing }
        if mix.jellyfish <= 0 { return .shell }
        return .jellyfish
    }

    private func chooseLane(kind: ObjectKind, arrival: Double) -> Lane? {
        var lanes = Array(Lane.allCases)
        rng.shuffle(&lanes)
        for lane in lanes where isFair(kind: kind, lane: lane, arrival: arrival) {
            return lane
        }
        return nil
    }

    private func isFair(kind: ObjectKind, lane: Lane, arrival: Double) -> Bool {
        let live = objects.filter { !$0.resolved }
        if kind.isCatchable {
            for other in live where other.kind.isCatchable {
                let gap = abs(arrival - other.arrivalTime)
                let needed: Double
                if lane == other.lane {
                    needed = Feel.catchableGap
                } else if Lane.isOppositeDiagonal(lane, other.lane) {
                    needed = Feel.diagonalGap
                } else {
                    needed = Feel.catchableGap
                }
                if gap < needed - 1e-6 { return false }
            }
            if phaseNumber == 1 {
                for other in live where other.kind.isCatchable {
                    if abs(arrival - other.arrivalTime) < Feel.phaseOneArrivalGap - 1e-6 {
                        return false
                    }
                }
            }
            if streakBlocks(lane) { return false }
            for other in live where other.kind == .jellyfish && other.lane == lane {
                if abs(arrival - other.arrivalTime) < Feel.jellyfishGap - 1e-6 { return false }
            }
            return true
        }

        for other in live where other.lane == lane {
            if abs(arrival - other.arrivalTime) < Feel.jellyfishGap - 1e-6 { return false }
        }
        let jellyCap = phaseNumber < 6 ? 1 : Feel.maxJellyfish
        let jellyCount = live.filter { $0.kind == .jellyfish }.count
        if jellyCount >= jellyCap { return false }

        var cluster: [(lane: Lane, arrival: Double)] = [(lane, arrival)]
        for other in live where other.kind == .jellyfish {
            cluster.append((other.lane, other.arrivalTime))
        }
        if jellyfishClusterOverflows(cluster) { return false }
        return true
    }

    private func jellyfishClusterOverflows(_ cluster: [(lane: Lane, arrival: Double)]) -> Bool {
        let sorted = cluster.sorted { $0.arrival < $1.arrival }
        for start in sorted.indices {
            var lanes = Set<Lane>()
            for next in start..<sorted.count {
                if sorted[next].arrival - sorted[start].arrival > Feel.jellyfishCluster + 1e-9 {
                    break
                }
                lanes.insert(sorted[next].lane)
                if lanes.count >= 3 { return true }
            }
        }
        return false
    }

    private func streakBlocks(_ lane: Lane) -> Bool {
        var streak = 0
        for item in catchableLaneHistory.reversed() {
            if item == lane { streak += 1 } else { break }
        }
        return streak >= Feel.maxLaneStreak
    }

    private func levelForSpeed() -> Int {
        var drop = 0
        if mercyCatchesRemaining > 0 { drop = 1 }
        if isBreather { drop = max(drop, 2) }
        return max(0, phaseIndex - drop)
    }

    private func currentMultiplier() -> Double {
        var value = ScoreMath.comboMultiplier(for: combo)
        if bigWaveBonusActive { value += 2 }
        return value
    }

    private func purge() {
        objects.removeAll { $0.resolved }
    }

    private func isFlying(_ object: ActiveObject) -> Bool {
        if case .flying = object.state { return true }
        return false
    }
}

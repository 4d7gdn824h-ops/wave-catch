import Foundation
import SwiftUI
import WaveCatchCore

final class GameModel: ObservableObject {
    enum Mode {
        case menu
        case playing
        case gameOver
    }

    @Published var mode: Mode = .menu
    @Published var score = 0
    @Published var lives = 3
    @Published var combo = 0
    @Published var multiplier = 1.0
    @Published var bestScore = 0
    @Published var runBestCombo = 0
    @Published var isNewBest = false
    @Published var safeLane = "none"
    @Published var jellyfishOnScreen = false
    @Published var pressedLane: Lane?
    @Published var showDebug = false
    @Published var showTuning = false
    @Published var showLicenses = false
    @Published var ringLit = false
    @Published var largePad = false
    @Published var wholeScreenPad = false
    @Published var swipeEnabled = false
    @Published var musicOn = true
    @Published var effectsOn = true
    @Published var againReady = false
    @Published var paused = false
    @Published var bigWavePhase: BigWavePhase = .idle
    @Published var tuning = TuningConfig()
    @Published var startPhase = 1
    @Published var callout = ""
    @Published var calloutTier = 0
    @Published var newBestRibbon = false
    @Published var sawNice = false
    @Published var sawGolden = false
    @Published var sawBigWave = false
    @Published var maxPitch = 0
    @Published var cardVisible = false

    let scene = GameScene()
    let uitest: Bool
    let seed: UInt64

    private(set) var session: GameSession?
    private let store = ScoreStore()
    private let haptics = HapticPlayer()
    private let tones = TonePlayer()
    private var againUnlock: DispatchWorkItem?
    private var glowClear: DispatchWorkItem?
    private var calloutClear: DispatchWorkItem?
    private var ribbonClear: DispatchWorkItem?
    private var bestAtStart = 0
    private var didRibbon = false
    private var ladder = 0
    private var slowUntil = 0.0
    private var nextSlow = 0.0
    private(set) var slowVisual = false
    /// Proof-only steering. Shipping play never sets these.
    private var proofDeath = false
    private var proofNice = false

    init() {
        let args = ProcessInfo.processInfo.arguments
        uitest = args.contains("-uitest") || args.contains("-autoplayDemo")
        var parsedSeed: UInt64 = uitest ? 7 : UInt64.random(in: 1...UInt64.max)
        if let index = args.firstIndex(of: "-seed"), index + 1 < args.count, let value = UInt64(args[index + 1]) {
            parsedSeed = value
        }
        seed = parsedSeed
        if uitest {
            UserDefaults.standard.removeObject(forKey: "wavecatch.bestScore")
            UserDefaults.standard.removeObject(forKey: "wavecatch.bestCombo")
            musicOn = true
            effectsOn = true
        } else {
            musicOn = Self.storedFlag("wavecatch.musicOn", default: true)
            effectsOn = Self.storedFlag("wavecatch.effectsOn", default: true)
        }
        bestScore = store.bestScore
        showTuning = args.contains("-showTuning")
        if uitest {
            tuning.speedMultiplier = 1
            tuning.spotlightGoldenShell = true
            tuning.spotlightBigWave = true
            startPhase = 1
        }
        scene.model = self
        tones.setMusicOn(musicOn)
        tones.setEffectsOn(effectsOn)
        tones.startLoops()
        haptics.prepareAll()
    }

    func setMusicOn(_ on: Bool) {
        musicOn = on
        tones.setMusicOn(on)
        if !uitest {
            UserDefaults.standard.set(on, forKey: "wavecatch.musicOn")
        }
    }

    func setEffectsOn(_ on: Bool) {
        effectsOn = on
        tones.setEffectsOn(on)
        if !uitest {
            UserDefaults.standard.set(on, forKey: "wavecatch.effectsOn")
        }
    }

    func startGame() {
        againUnlock?.cancel()
        let next = GameSession(seed: seed, tuning: tuning.clamped(), startPhase: min(10, max(1, startPhase)))
        session = next
        scene.attach(next)
        score = 0
        lives = 3
        combo = 0
        multiplier = 1
        runBestCombo = 0
        isNewBest = false
        againReady = false
        cardVisible = false
        paused = false
        bigWavePhase = .idle
        safeLane = "none"
        jellyfishOnScreen = false
        ringLit = false
        callout = ""
        newBestRibbon = false
        sawNice = false
        sawGolden = false
        sawBigWave = false
        maxPitch = 0
        ladder = 0
        bestAtStart = bestScore
        didRibbon = false
        slowVisual = false
        proofDeath = false
        proofNice = false
        mode = .playing
        haptics.prepareAll()
        tones.startLoops()
    }

    func setLane(_ lane: Lane) {
        guard mode == .playing, !paused, let session else { return }
        session.setPosition(lane)
        pressedLane = lane
        glowClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.pressedLane == lane { self?.pressedLane = nil }
        }
        glowClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func togglePause() {
        guard mode == .playing, let session else { return }
        paused.toggle()
        session.setPaused(paused)
    }

    func advance(dt: Double) {
        tones.update(dt: dt)
        guard mode == .playing, !paused, let session else { return }
        steerProof(session)
        session.tuning = tuning.clamped()
        let now = Date().timeIntervalSince1970
        slowVisual = now < slowUntil
        let sim = slowVisual ? dt * 0.5 : dt
        let events = session.tick(dt: sim)
        publish(session)
        react(to: events, session: session)
        noteProof(session)
        scene.present(events, session: session)
    }

    var timeScale: CGFloat {
        if session?.hitStopRemaining ?? 0 > 0 { return 0 }
        if slowVisual { return 0.5 }
        return 1
    }

    /// `-uitest` only. Catch until Nice and the Big Wave breather, then miss on purpose.
    private func steerProof(_ session: GameSession) {
        guard uitest else { return }
        let live = session.liveObjects
        if !proofDeath {
            if let lane = session.suggestedLane() {
                session.setPosition(lane)
            }
            if let jelly = live.filter({ $0.kind == .jellyfish }).min(by: { $0.arrivalTime < $1.arrivalTime }),
               jelly.lane == session.position,
               jelly.step >= 4 || jelly.arrivalTime - session.time < session.stepInterval {
                let away = Lane.allCases.first { candidate in
                    candidate != jelly.lane && !live.contains { $0.kind == .jellyfish && $0.lane == candidate }
                }
                if let away {
                    session.setPosition(away)
                }
            }
        } else if let lane = session.suggestedLane() {
            session.setPosition(lane.opposite)
        }
    }

    private func noteProof(_ session: GameSession) {
        guard uitest, !proofDeath else { return }
        if session.combo >= 5 {
            proofNice = true
        }
        if proofNice && session.bigWavePhase == .breather {
            proofDeath = true
        }
    }

    private func publish(_ session: GameSession) {
        if score != session.score { score = session.score }
        if lives != session.lives { lives = session.lives }
        if combo != session.combo { combo = session.combo }
        if multiplier != session.multiplier { multiplier = session.multiplier }
        if runBestCombo != session.bestCombo { runBestCombo = session.bestCombo }
        if bigWavePhase != session.bigWavePhase {
            bigWavePhase = session.bigWavePhase
            if bigWavePhase != .idle { sawBigWave = true }
        }
        let lane = session.suggestedLane()?.rawValue ?? "none"
        if safeLane != lane { safeLane = lane }
        let jelly = session.liveObjects.contains { $0.kind == .jellyfish }
        if jellyfishOnScreen != jelly { jellyfishOnScreen = jelly }
        let golden = session.liveObjects.contains { $0.kind == .goldenShell }
        if golden { sawGolden = true }
        let lit = session.liveObjects.contains { $0.telegraph }
        if ringLit != lit { ringLit = lit }
        if !didRibbon && score > bestAtStart {
            didRibbon = true
            newBestRibbon = true
            tones.play("new-best", pan: 0, volume: 0.8)
            tones.duck()
            ribbonClear?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.newBestRibbon = false }
            ribbonClear = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }

    private func react(to events: [GameEvent], session: GameSession) {
        for event in events {
            switch event {
            case .caught(_, let lane, let kind, _, let combo, let close):
                haptics.catchFeedback(kind: kind.rawValue, close: close, wave: session.bigWavePhase == .active)
                playCatch(kind: kind, lane: lane, combo: combo)
                if close {
                    let now = Date().timeIntervalSince1970
                    if now >= nextSlow {
                        slowUntil = now + Feel.nearMissSlow
                        nextSlow = now + Feel.nearMissCooldown
                    }
                }
            case .missed(_, let lane, _, let lifeLost):
                ladder = 0
                if lifeLost {
                    haptics.miss()
                    tones.play("miss", pan: pan(lane), volume: 0.85)
                }
            case .stung(_, let lane, _):
                ladder = 0
                haptics.sting()
                tones.play("sting", pan: pan(lane), volume: 0.9)
            case .dodged(_, let lane):
                tones.play("ring", pan: pan(lane), volume: 0.35)
            case .stepped(let tick, let lanes):
                let name = tick % 2 == 0 ? "tick" : "tock"
                tones.play(name, pan: pan(lanes), volume: 0.2)
            case .telegraph(_, let lane, _):
                tones.play("ring", pan: pan(lane), volume: 0.28)
            case .tierReached(let name, _):
                ladder = 0
                haptics.tier()
                tones.play("tier", pan: 0, volume: 0.7)
                tones.duck()
                showCallout(name, tier: ScoreMath.tierIndex(for: session.combo))
            case .bigWaveWarning:
                sawBigWave = true
                tones.play("whoosh", pan: 0, volume: 0.7)
                tones.duck()
                if callout == "Nice!" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                        self?.showCallout("BIG WAVE!", tier: 4)
                    }
                } else {
                    showCallout("BIG WAVE!", tier: 4)
                }
            case .bigWaveStart:
                tones.setWave(true)
            case .bigWaveEnd:
                tones.setWave(false)
                tones.play("crash", pan: 0, volume: 0.75)
            case .gameOver:
                finish(session)
            default:
                break
            }
        }
    }

    private func showCallout(_ text: String, tier: Int) {
        callout = text
        calloutTier = tier
        if text == "Nice!" { sawNice = true }
        calloutClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.callout == text { self?.callout = "" }
        }
        calloutClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)
    }

    private func finish(_ session: GameSession) {
        let previous = bestAtStart
        isNewBest = session.score > previous
        store.record(score: session.score, combo: session.bestCombo)
        bestScore = store.bestScore
        runBestCombo = session.bestCombo
        score = session.score
        lives = 0
        againReady = false
        cardVisible = false
        againUnlock?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.cardVisible = true
            self.againReady = true
            self.mode = .gameOver
            self.tones.play("fanfare", pan: 0, volume: 0.8)
            self.tones.duck()
        }
        againUnlock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Feel.againInputLock, execute: work)
    }

    private func playCatch(kind: ObjectKind, lane: Lane, combo: Int) {
        if kind == .goldenShell {
            tones.play("golden", pan: pan(lane), volume: 0.9)
            return
        }
        let name = "catch-\(ladder)"
        if ladder > maxPitch { maxPitch = ladder }
        tones.play(name, pan: pan(lane), volume: 0.85)
        if ScoreMath.callout(for: combo) == nil {
            ladder = (ladder + 1) % 8
        }
    }

    private func pan(_ lane: Lane) -> Float {
        lane.isRight ? 0.55 : -0.55
    }

    private func pan(_ lanes: [Lane]) -> Float {
        guard !lanes.isEmpty else { return 0 }
        let total = lanes.reduce(Float(0)) { $0 + ($1.isRight ? 0.45 : -0.45) }
        return total / Float(lanes.count)
    }

    private static func storedFlag(_ key: String, default defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil { return defaultValue }
        return UserDefaults.standard.bool(forKey: key)
    }
}

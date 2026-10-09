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
    @Published var ringLit = false
    @Published var largePad = false
    @Published var wholeScreenPad = false
    @Published var swipeEnabled = false
    @Published var muted = false
    @Published var againReady = false
    @Published var paused = false
    @Published var bigWavePhase: BigWavePhase = .idle
    @Published var tuning = TuningConfig()
    @Published var startPhase = 1

    let scene = GameScene()
    let uitest: Bool
    let seed: UInt64

    private(set) var session: GameSession?
    private let store = ScoreStore()
    private let haptics = HapticPlayer()
    private let tones = TonePlayer()
    private var againUnlock: DispatchWorkItem?
    private var glowClear: DispatchWorkItem?
    private var ringLitUntil = 0.0
    /// Proof-only steering. Shipping play never sets these.
    private var proofDeath = false
    private var proofSawPass = false
    private var proofCruiseUntil: Double?

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
        }
        bestScore = store.bestScore
        showTuning = args.contains("-showTuning")
        if uitest {
            tuning.speedMultiplier = 0.62
            tuning.demoSpotlightJellyfish = true
            startPhase = 1
        }
        scene.model = self
        tones.start()
        haptics.prepareAll()
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
        paused = false
        bigWavePhase = .idle
        safeLane = "none"
        jellyfishOnScreen = false
        ringLit = false
        ringLitUntil = 0
        proofDeath = false
        proofSawPass = false
        proofCruiseUntil = nil
        mode = .playing
        haptics.prepareAll()
    }

    func setLane(_ lane: Lane) {
        guard mode == .playing, !paused, let session else { return }
        let changed = session.position != lane
        session.setPosition(lane)
        pressedLane = lane
        glowClear?.cancel()
        let work = DispatchWorkItem { [weak self] in
            if self?.pressedLane == lane { self?.pressedLane = nil }
        }
        glowClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        if changed && !muted {
            tones.play(frequency: 280, duration: 0.05, volume: 0.12, pan: lane.isRight ? 0.4 : -0.4)
        }
    }

    func togglePause() {
        guard mode == .playing, let session else { return }
        paused.toggle()
        session.setPaused(paused)
    }

    func advance(dt: Double) {
        guard mode == .playing, !paused, let session else { return }
        steerProof(session)
        session.tuning = tuning.clamped()
        let events = session.tick(dt: dt)
        publish(session)
        react(to: events, session: session)
        noteProof(events, session: session)
        scene.present(events, session: session)
    }

    /// `-uitest` only. Follow the next catchable, step off a jellyfish, then miss on purpose after the combo climbs.
    private func steerProof(_ session: GameSession) {
        guard uitest else { return }
        let live = session.liveObjects
        if !proofDeath {
            if let lane = session.suggestedLane() {
                session.setPosition(lane)
            }
            if let jelly = live.filter({ $0.kind == .jellyfish }).min(by: { $0.arrivalTime < $1.arrivalTime }),
               jelly.lane == session.position,
               jelly.arrivalTime - session.time < 0.55 {
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

    private func noteProof(_ events: [GameEvent], session: GameSession) {
        guard uitest, !proofDeath else { return }
        for event in events {
            switch event {
            case .jellyfishPassed, .dodged:
                proofSawPass = true
            default:
                break
            }
        }
        if proofSawPass, session.combo >= 10 {
            if proofCruiseUntil == nil {
                proofCruiseUntil = session.time + 1.6
            }
            if let until = proofCruiseUntil, session.time >= until {
                proofDeath = true
            }
        } else {
            proofCruiseUntil = nil
        }
    }

    private func publish(_ session: GameSession) {
        if score != session.score { score = session.score }
        if lives != session.lives { lives = session.lives }
        if combo != session.combo { combo = session.combo }
        if multiplier != session.multiplier { multiplier = session.multiplier }
        if runBestCombo != session.bestCombo { runBestCombo = session.bestCombo }
        if bigWavePhase != session.bigWavePhase { bigWavePhase = session.bigWavePhase }
        let lane = session.suggestedLane()?.rawValue ?? "none"
        if safeLane != lane { safeLane = lane }
        let jelly = session.liveObjects.contains { $0.kind == .jellyfish }
        if jellyfishOnScreen != jelly { jellyfishOnScreen = jelly }
        if session.liveObjects.contains(where: { $0.telegraph }) {
            ringLitUntil = session.time + 0.35
        }
        let lit = session.time < ringLitUntil
        if ringLit != lit { ringLit = lit }
    }

    private func react(to events: [GameEvent], session: GameSession) {
        for event in events {
            switch event {
            case .caught(_, let lane, let kind, _, _, let close):
                haptics.catchFeedback(kind: kind.rawValue, close: close, wave: session.bigWavePhase == .active)
                playCatch(kind: kind, lane: lane, close: close, combo: session.combo)
            case .missed(_, let lane, _, let lifeLost):
                if lifeLost {
                    haptics.miss()
                    playMiss(lane: lane)
                }
            case .stung(_, let lane, _):
                haptics.sting()
                playSting(lane: lane)
            case .dodged(_, let lane):
                tones.play(frequency: 620, duration: 0.08, volume: 0.35, pan: pan(lane))
            case .telegraph(_, let lane, _):
                let pitch = lane.isUpper ? semitone(880, steps: 5) : 880
                tones.play(frequency: pitch * 2, duration: 0.04, volume: 0.18, pan: pan(lane))
            case .bigWaveWarning:
                tones.play(frequency: 220, duration: 0.45, volume: 0.4, pan: 0, sweep: 500)
            case .bigWaveStart:
                tones.play(frequency: 140, duration: 0.25, volume: 0.45, pan: 0)
            case .gameOver:
                finish(session)
            default:
                break
            }
        }
    }

    private func finish(_ session: GameSession) {
        let previous = bestScore
        isNewBest = session.score > previous
        store.record(score: session.score, combo: session.bestCombo)
        bestScore = store.bestScore
        runBestCombo = session.bestCombo
        score = session.score
        lives = 0
        mode = .gameOver
        againReady = false
        againUnlock?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.againReady = true
        }
        againUnlock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Feel.againInputLock, execute: work)
        if !muted {
            tones.play(frequency: 360, duration: 0.35, volume: 0.4, pan: 0, sweep: -260)
        }
    }

    private func playCatch(kind: ObjectKind, lane: Lane, close: Bool, combo: Int) {
        guard !muted else { return }
        let steps = min(12, combo / 5)
        let base: Double
        switch kind {
        case .shell: base = 740
        case .board: base = 520
        case .lifeRing: base = 988
        case .jellyfish: base = 700
        }
        let pitched = semitone(lane.isUpper ? semitone(base, steps: 5) : base, steps: steps)
        tones.play(frequency: close ? pitched * 1.25 : pitched, duration: close ? 0.09 : 0.07, volume: 0.45, pan: pan(lane))
    }

    private func playMiss(lane: Lane) {
        guard !muted else { return }
        tones.play(frequency: 420, duration: 0.18, volume: 0.5, pan: pan(lane), sweep: -240)
    }

    private func playSting(lane: Lane) {
        guard !muted else { return }
        tones.play(frequency: 90, duration: 0.2, volume: 0.5, pan: pan(lane))
        tones.play(frequency: 1800, duration: 0.05, volume: 0.3, pan: pan(lane))
    }

    private func pan(_ lane: Lane) -> Float {
        lane.isRight ? 0.5 : -0.5
    }

    private func semitone(_ frequency: Double, steps: Int) -> Double {
        frequency * pow(2, Double(steps) / 12)
    }
}

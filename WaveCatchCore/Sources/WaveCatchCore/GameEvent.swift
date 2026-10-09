import Foundation

public enum BigWavePhase: String, Equatable {
    case idle
    case warning
    case active
    case breather
}

public struct LiveObject: Equatable {
    public let id: Int
    public let kind: ObjectKind
    public let lane: Lane
    public let arrivalTime: Double
    public let travel: Double
    public let progress: Double
    public let wobbling: Bool
    public let telegraph: Bool
    public let hopSalt: UInt64
}

public enum GameEvent: Equatable {
    case spawned(id: Int, kind: ObjectKind, lane: Lane, arrival: Double, travel: Double)
    case telegraph(id: Int, lane: Lane, kind: ObjectKind)
    case caught(id: Int, lane: Lane, kind: ObjectKind, points: Int, combo: Int, close: Bool)
    case missed(id: Int, lane: Lane, lives: Int, lifeLost: Bool)
    case stung(id: Int, lane: Lane, lives: Int)
    case jellyfishPassed(id: Int, lane: Lane)
    case dodged(id: Int, lane: Lane)
    case jellyfishFaded(id: Int, lane: Lane)
    case comboChanged(combo: Int, multiplier: Double)
    case bigWaveWarning
    case bigWaveStart
    case bigWaveBonusLost
    case bigWaveEnd
    case gameOver(score: Int, bestCombo: Int)
}

public enum Feel {
    public static let lateGrace = 0.080
    public static let stingConfirm = 0.040
    public static let dodgeMemory = 0.150
    public static let mercySilence = 1.0
    public static let mercyCatches = 8
    public static let mercyClearSpawns = 3
    public static let catchableGap = 0.300
    public static let diagonalGap = 0.450
    public static let jellyfishGap = 0.400
    public static let jellyfishCluster = 0.600
    public static let maxJellyfish = 2
    public static let maxLaneStreak = 4
    public static let phaseOneArrivalGap = 1.2
    public static let bigWaveWarning = 1.5
    public static let bigWaveBreather = 3.0
    public static let hitStopMiss = 0.090
    public static let hitStopSting = 0.120
    public static let againInputLock = 0.600
    public static let poseTween = 0.060
    public static let shakeMaxPoints = 10.0
    public static let shakeMaxDuration = 0.300
}

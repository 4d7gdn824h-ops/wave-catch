import Foundation

/// Phase speed curve. `level` is 0 for phase 1. After phase 10 it keeps climbing.
public enum SpeedCurve {
    public static func travelTime(level: Int) -> Double {
        let l = max(0, level)
        return max(0.90, 2.60 * pow(0.92, Double(l)))
    }

    public static func spawnInterval(level: Int) -> Double {
        let l = max(0, level)
        return max(0.40, 1.60 * pow(0.88, Double(l)))
    }

    public static func maxOnScreen(level: Int) -> Int {
        let l = max(0, level)
        return min(5, 2 + l / 3)
    }

    public static func travelTime(level: Int, kind: ObjectKind, tuning: TuningConfig) -> Double {
        let tuned = tuning.clamped()
        return travelTime(level: level) / tuned.speedMultiplier * kind.travelScale
    }

    public static func spawnInterval(level: Int, tuning: TuningConfig, bigWave: Bool) -> Double {
        let tuned = tuning.clamped()
        let base = spawnInterval(level: level) / tuned.spawnRateMultiplier
        if bigWave {
            return max(0.30, 0.50 * base)
        }
        return base
    }

    /// How early the catch spot lights, in seconds.
    public static func telegraphLead(travel: Double) -> Double {
        min(0.400, 0.40 * travel)
    }
}

public enum ScoreMath {
    public static func comboMultiplier(for combo: Int) -> Double {
        if combo >= 50 { return 3 }
        if combo >= 25 { return 2 }
        if combo >= 10 { return 1.5 }
        return 1
    }

    public static func points(base: Int, multiplier: Double) -> Int {
        guard base > 0 else { return 0 }
        return Int((Double(base) * multiplier).rounded(.up))
    }
}

import Foundation

/// Shared step clock. `level` is 0 for phase 1.
/// The interval is a gear: it changes when the phase changes, not after every catch.
public enum SpeedCurve {
    /// 0.60 s at phase 1, 0.18 s by phase 10, then the floor holds.
    public static func stepInterval(level: Int) -> Double {
        let span = min(9, max(0, level))
        return 0.60 - (0.42 * Double(span) / 9.0)
    }

    /// Time from the first standing position to the drop. Four advances, five positions.
    public static func travelTime(level: Int) -> Double {
        stepInterval(level: level) * Double(LaneGeometry.hopsToDrop)
    }

    public static func spawnInterval(level: Int) -> Double {
        let l = max(0, level)
        return max(0.40, 1.60 * pow(0.88, Double(l)))
    }

    public static func maxOnScreen(level: Int) -> Int {
        let l = max(0, level)
        return min(5, 2 + l / 3)
    }

    /// Every kind shares the step clock. `speedMultiplier` shortens the step.
    public static func travelTime(level: Int, kind: ObjectKind, tuning: TuningConfig) -> Double {
        let tuned = tuning.clamped()
        _ = kind
        return travelTime(level: level) / tuned.speedMultiplier
    }

    public static func spawnInterval(level: Int, tuning: TuningConfig, bigWave: Bool) -> Double {
        let tuned = tuning.clamped()
        let base = spawnInterval(level: level) / tuned.spawnRateMultiplier
        if bigWave {
            return max(0.30, 0.50 * base)
        }
        return base
    }

    /// The ring lights one step before the drop.
    public static func telegraphLead(travel: Double) -> Double {
        travel / Double(LaneGeometry.hopsToDrop)
    }

    /// A tap in the last fraction of a step, and always for at least 80 ms, still counts.
    public static func lateGrace(stepInterval: Double) -> Double {
        max(Feel.lateGrace, stepInterval * 0.20)
    }

    /// How many step-clock ticks to wait between spawns so the spawn stays on a tick.
    public static func spawnGapTicks(spawnInterval: Double, stepInterval: Double) -> Int {
        let step = max(0.05, stepInterval)
        return max(1, Int((spawnInterval / step).rounded()))
    }
}

public enum ScoreMath {
    public static let tierCombos = [5, 10, 20, 35]

    public static func comboMultiplier(for combo: Int) -> Double {
        if combo >= 35 { return 4 }
        if combo >= 20 { return 3 }
        if combo >= 10 { return 2 }
        if combo >= 5 { return 1.5 }
        return 1
    }

    /// 0 before Nice, then 1...4 for the four callouts.
    public static func tierIndex(for combo: Int) -> Int {
        if combo >= 35 { return 4 }
        if combo >= 20 { return 3 }
        if combo >= 10 { return 2 }
        if combo >= 5 { return 1 }
        return 0
    }

    /// Non-nil only on the catch that crosses a tier.
    public static func callout(for combo: Int) -> String? {
        switch combo {
        case 5: return "Nice!"
        case 10: return "Rad!"
        case 20: return "Tubular!"
        case 35: return "Wave Master!"
        default: return nil
        }
    }

    public static func points(base: Int, multiplier: Double) -> Int {
        guard base > 0 else { return 0 }
        return Int((Double(base) * multiplier).rounded(.up))
    }
}

import Foundation

public enum Motion {
    /// Smooth progress from 0 to 1. Catchables move steadily. Jellyfish hop, but the path is still continuous.
    public static func visualProgress(
        kind: ObjectKind,
        spawnTime: Double,
        arrivalTime: Double,
        now: Double,
        hopSalt: UInt64
    ) -> Double {
        let duration = max(1e-6, arrivalTime - spawnTime)
        let linear = min(1, max(0, (now - spawnTime) / duration))
        if kind != .jellyfish {
            return linear
        }
        return jellyfishHop(linear, salt: hopSalt)
    }

    /// Monotone hop curve. f(0) = 0, f(1) = 1, and the middle is not the linear halfway point.
    public static func jellyfishHop(_ linear: Double, salt: UInt64) -> Double {
        if linear <= 0 { return 0 }
        if linear >= 1 { return 1 }
        let jiggle = Double(salt % 5) * 0.02
        let times = [0.0, 0.18 + jiggle, 0.40, 0.56 + jiggle, 0.76, 0.90, 1.0]
        let progress = [0.0, 0.0, 0.36, 0.36, 0.72, 0.72, 1.0]
        for index in 0..<(times.count - 1) {
            let end = times[index + 1]
            if linear <= end {
                let span = max(1e-6, end - times[index])
                let local = (linear - times[index]) / span
                return progress[index] + (progress[index + 1] - progress[index]) * local
            }
        }
        return 1
    }
}

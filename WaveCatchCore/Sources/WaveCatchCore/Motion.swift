import Foundation

/// Discrete chute positions. Items occupy one step at a time and do not glide.
public enum Motion {
    public static func progress(forStep step: Int) -> Double {
        let clamped = min(LaneGeometry.stepCount, max(1, step))
        return Double(clamped - 1) / Double(LaneGeometry.stepCount - 1)
    }
}

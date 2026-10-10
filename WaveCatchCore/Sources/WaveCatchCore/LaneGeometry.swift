import Foundation

/// Screen-normalised wave chutes.
///
/// This is the only place that decides where objects travel. Coordinates use the
/// full landscape screen: x grows right, y grows down. Each lane is a crescent
/// tube of five standing positions. Left chutes begin on the left and curl down
/// toward the surfer. Right chutes begin on the right and curl down toward the
/// surfer. Items snap from one position to the next. They do not glide.
public enum LaneGeometry {
    public struct Point: Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    /// Standing positions on a chute, including the drop.
    public static let stepCount = 5
    /// Advances from position 1 to the drop at position 5.
    public static let hopsToDrop = 4

    public static func endpoints(_ lane: Lane) -> (start: Point, end: Point) {
        switch lane {
        case .upperLeft:
            return (Point(x: 0.28, y: 0.11), Point(x: 0.42, y: 0.42))
        case .upperRight:
            return (Point(x: 0.72, y: 0.11), Point(x: 0.58, y: 0.42))
        case .lowerLeft:
            return (Point(x: 0.26, y: 0.46), Point(x: 0.40, y: 0.76))
        case .lowerRight:
            return (Point(x: 0.74, y: 0.46), Point(x: 0.60, y: 0.76))
        }
    }

    /// Off-chord bend that pulls the tube into a crescent.
    private static func bend(_ lane: Lane) -> Point {
        switch lane {
        case .upperLeft:
            return Point(x: 0.48, y: 0.16)
        case .upperRight:
            return Point(x: 0.52, y: 0.16)
        case .lowerLeft:
            return Point(x: 0.46, y: 0.50)
        case .lowerRight:
            return Point(x: 0.54, y: 0.50)
        }
    }

    /// `progress` 0 is position 1 and 1 is the drop. The path is a quadratic crescent.
    public static func point(lane: Lane, progress: Double) -> Point {
        let t = min(1, max(0, progress))
        let ends = endpoints(lane)
        let control = bend(lane)
        let stay = 1 - t
        return Point(
            x: stay * stay * ends.start.x + 2 * stay * t * control.x + t * t * ends.end.x,
            y: stay * stay * ends.start.y + 2 * stay * t * control.y + t * t * ends.end.y
        )
    }

    /// `step` is 1...5. Values outside that range clamp.
    public static func point(lane: Lane, step: Int) -> Point {
        let clamped = min(stepCount, max(1, step))
        let progress = Double(clamped - 1) / Double(stepCount - 1)
        return point(lane: lane, progress: progress)
    }

    public static func catchSpot(_ lane: Lane) -> Point {
        point(lane: lane, step: stepCount)
    }

    /// Where the surfer's body sits, low in the water above the sand. Poses offset from here.
    public static let surferAnchor = Point(x: 0.50, y: 0.58)
}

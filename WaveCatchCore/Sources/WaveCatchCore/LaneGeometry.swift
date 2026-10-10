import Foundation

/// Screen-normalised wave chutes.
///
/// This is the only place that decides where objects travel. Coordinates use the
/// full landscape screen: x grows right, y grows down. Each lane is a straight
/// slanted chute of five standing positions. Left chutes begin on the left and
/// slope down toward the surfer. Right chutes begin on the right and slope down
/// toward the surfer. Items snap from one position to the next. They do not glide.
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
            return (Point(x: 0.26, y: 0.20), Point(x: 0.40, y: 0.38))
        case .upperRight:
            return (Point(x: 0.74, y: 0.20), Point(x: 0.60, y: 0.38))
        case .lowerLeft:
            return (Point(x: 0.24, y: 0.42), Point(x: 0.38, y: 0.50))
        case .lowerRight:
            return (Point(x: 0.76, y: 0.42), Point(x: 0.62, y: 0.50))
        }
    }

    /// `progress` 0 is position 1 and 1 is the drop. The path is a straight chord.
    public static func point(lane: Lane, progress: Double) -> Point {
        let u = min(1, max(0, progress))
        let ends = endpoints(lane)
        return Point(
            x: ends.start.x + (ends.end.x - ends.start.x) * u,
            y: ends.start.y + (ends.end.y - ends.start.y) * u
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

    /// Where the surfer's body sits. Poses offset from here.
    public static let surferAnchor = Point(x: 0.50, y: 0.50)
}

import Foundation

/// Screen-normalised paths for the four lanes.
///
/// This is the only place that decides where objects travel. Coordinates use the
/// full landscape screen: x grows right, y grows down. Corner buttons own the
/// corners, so every sample stays in the middle band and on screen.
///
/// Upper lanes leave the lip of the curling wave and arc down toward the upper
/// corner buttons. Lower lanes skim in from the left and right along the
/// waterline, with a small bob, and finish above the lower corner buttons.
/// A 1.3× sprite on a lower sample stays at least 12 points clear of those
/// buttons on a landscape Pro Max, in both orientations. The surfer stays in
/// the center. Paths stay inset so a sprite drawn at 1.3× around each sample
/// remains on screen.
public enum LaneGeometry {
    public struct Point: Equatable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public static func point(lane: Lane, progress: Double) -> Point {
        let u = min(1, max(0, progress))
        switch lane {
        case .upperLeft:
            return quadratic(
                Point(x: 0.40, y: 0.26),
                Point(x: 0.16, y: 0.30),
                Point(x: 0.24, y: 0.38),
                u
            )
        case .upperRight:
            return quadratic(
                Point(x: 0.60, y: 0.26),
                Point(x: 0.84, y: 0.30),
                Point(x: 0.76, y: 0.38),
                u
            )
        case .lowerLeft:
            let y = 0.496 + 0.008 * sin(u * Double.pi * 3)
            return Point(x: 0.22 + 0.10 * u, y: y)
        case .lowerRight:
            let y = 0.496 + 0.008 * sin(u * Double.pi * 3 + 0.6)
            return Point(x: 0.78 - 0.10 * u, y: y)
        }
    }

    public static func catchSpot(_ lane: Lane) -> Point {
        point(lane: lane, progress: 1)
    }

    /// Where the surfer's body sits, as a fraction of the screen. Poses offset from here.
    public static let surferAnchor = Point(x: 0.50, y: 0.50)

    private static func quadratic(_ a: Point, _ control: Point, _ b: Point, _ u: Double) -> Point {
        let inverse = 1 - u
        let x = inverse * inverse * a.x + 2 * inverse * u * control.x + u * u * b.x
        let y = inverse * inverse * a.y + 2 * inverse * u * control.y + u * u * b.y
        return Point(x: x, y: y)
    }
}

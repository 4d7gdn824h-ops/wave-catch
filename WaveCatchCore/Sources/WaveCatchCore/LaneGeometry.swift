import Foundation

/// Screen-normalised paths for the four lanes.
///
/// This is the only place that decides where objects travel. Change it here if the
/// layout is revised. Coordinates use a full portrait screen: x grows right, y grows
/// down. The touch pad occupies the bottom 45 percent, so every sample stays above y = 0.55.
///
/// Upper lanes leave the lip of the curling wave and arc down to the surfer's hands.
/// Lower lanes skim in from the left and right along the waterline, with a small bob.
/// Paths stay inset from the screen edges so a sprite drawn at 1.3× around each
/// sample is fully on screen. Nothing is aimed out of a screen corner.
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
                Point(x: 0.30, y: 0.17),
                Point(x: 0.05, y: 0.22),
                Point(x: 0.36, y: 0.37),
                u
            )
        case .upperRight:
            return quadratic(
                Point(x: 0.70, y: 0.17),
                Point(x: 0.95, y: 0.22),
                Point(x: 0.64, y: 0.37),
                u
            )
        case .lowerLeft:
            let y = 0.46 + 0.012 * sin(u * Double.pi * 3)
            return Point(x: 0.14 + 0.26 * u, y: y)
        case .lowerRight:
            let y = 0.46 + 0.012 * sin(u * Double.pi * 3 + 0.6)
            return Point(x: 0.86 - 0.26 * u, y: y)
        }
    }

    public static func catchSpot(_ lane: Lane) -> Point {
        point(lane: lane, progress: 1)
    }

    /// Where the surfer's body sits, as a fraction of the screen. Poses offset from here.
    public static let surferAnchor = Point(x: 0.50, y: 0.43)

    private static func quadratic(_ a: Point, _ control: Point, _ b: Point, _ u: Double) -> Point {
        let inverse = 1 - u
        let x = inverse * inverse * a.x + 2 * inverse * u * control.x + u * u * b.x
        let y = inverse * inverse * a.y + 2 * inverse * u * control.y + u * u * b.y
        return Point(x: x, y: y)
    }
}

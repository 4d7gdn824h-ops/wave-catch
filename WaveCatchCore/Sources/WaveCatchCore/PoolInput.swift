import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Full-scene diagonal zones and the pose that aims the board nose at a wall.
/// Coordinates are SpriteKit's: origin bottom-left, +y north.
public enum PoolInput {
    /// The two diagonals split the entire view, edge to edge. The pool rect is not involved.
    public static func side(x: Double, y: Double, width: Double, height: Double) -> Side {
        let dx = x - width / 2
        let dy = y - height / 2
        let nx = abs(dx) / max(width / 2, 1)
        let ny = abs(dy) / max(height / 2, 1)
        if ny >= nx {
            return dy >= 0 ? .north : .south
        }
        return dx >= 0 ? .east : .west
    }

    /// SpriteKit `zRotation` that aims local +y (the board nose) at `side`.
    public static func noseRotation(facing side: Side) -> Double {
        switch side {
        case .north: return 0
        case .east: return -.pi / 2
        case .south: return .pi
        case .west: return .pi / 2
        }
    }

    /// Unit nose after `noseRotation`. East is +x, north is +y.
    public static func noseVector(facing side: Side) -> (x: Double, y: Double) {
        let angle = noseRotation(facing: side)
        return (x: -sin(angle), y: cos(angle))
    }
}

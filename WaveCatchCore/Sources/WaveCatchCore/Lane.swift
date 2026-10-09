import Foundation

/// Four catch positions. The surfer is always in exactly one of them.
public enum Lane: String, CaseIterable, Equatable, Hashable, Codable {
    case upperLeft
    case upperRight
    case lowerLeft
    case lowerRight

    public var isUpper: Bool {
        self == .upperLeft || self == .upperRight
    }

    public var isRight: Bool {
        self == .upperRight || self == .lowerRight
    }

    /// Opposite diagonal, used by the fairness gap and by debug swipes.
    public var opposite: Lane {
        switch self {
        case .upperLeft: return .lowerRight
        case .upperRight: return .lowerLeft
        case .lowerLeft: return .upperRight
        case .lowerRight: return .upperLeft
        }
    }

    public static func isOppositeDiagonal(_ a: Lane, _ b: Lane) -> Bool {
        a.opposite == b && a != b
    }
}

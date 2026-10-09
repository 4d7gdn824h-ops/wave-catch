import Foundation

public enum ObjectKind: String, Equatable, Hashable, Codable {
    case shell
    case board
    case lifeRing
    case jellyfish

    public var basePoints: Int {
        switch self {
        case .shell: return 1
        case .board: return 2
        case .lifeRing: return 3
        case .jellyfish: return 0
        }
    }

    public var isCatchable: Bool { self != .jellyfish }

    /// Travel-time scale. Boards are quicker, jellyfish are slower.
    public var travelScale: Double {
        switch self {
        case .board: return 0.90
        case .jellyfish: return 1.10
        case .shell, .lifeRing: return 1.0
        }
    }
}

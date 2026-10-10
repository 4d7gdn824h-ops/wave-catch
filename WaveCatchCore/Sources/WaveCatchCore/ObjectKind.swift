import Foundation

public enum ObjectKind: String, Equatable, Hashable, Codable {
    case shell
    case board
    case lifeRing
    case goldenShell
    case jellyfish

    public var basePoints: Int {
        switch self {
        case .shell: return 1
        case .board: return 2
        case .lifeRing: return 3
        case .goldenShell: return 5
        case .jellyfish: return 0
        }
    }

    public var isCatchable: Bool { self != .jellyfish }
}

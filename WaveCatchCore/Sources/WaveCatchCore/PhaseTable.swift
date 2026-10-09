import Foundation

public enum PhaseTable {
    /// Catches required to clear phases 1...10. Later phases use 15.
    public static let clearTargets: [Int] = [8, 10, 10, 10, 12, 12, 12, 15, 15, 15]

    public static func clearTarget(phaseNumber: Int) -> Int {
        if phaseNumber >= 1 && phaseNumber <= clearTargets.count {
            return clearTargets[phaseNumber - 1]
        }
        return 15
    }

    /// Spawn weights as percentages: shell, board, life ring, jellyfish.
    public static func mix(phaseNumber: Int) -> (shell: Double, board: Double, ring: Double, jellyfish: Double) {
        switch max(1, phaseNumber) {
        case 1: return (100, 0, 0, 0)
        case 2: return (85, 15, 0, 0)
        case 3: return (75, 20, 5, 0)
        case 4: return (70, 20, 5, 5)
        case 5: return (62, 20, 6, 12)
        case 6: return (60, 20, 6, 14)
        case 7: return (58, 22, 6, 14)
        case 8: return (55, 22, 7, 16)
        case 9: return (52, 24, 7, 17)
        default: return (50, 24, 8, 18)
        }
    }

    /// Big Wave follows clears of phases 4, 7, 10, then every third phase.
    public static func bigWaveFollowsClear(of phaseNumber: Int) -> Bool {
        phaseNumber >= 4 && (phaseNumber - 4) % 3 == 0
    }
}

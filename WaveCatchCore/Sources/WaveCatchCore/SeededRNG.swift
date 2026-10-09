import Foundation

/// SplitMix64. Same seed, same stream, on every platform.
public struct SeededRNG: Equatable {
    public private(set) var state: UInt64

    public init(seed: UInt64) {
        // A zero seed still has to move, so mix it once up front.
        self.state = seed == 0 ? 0xA5A5_5A5A_1234_5678 : seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Value in [0, 1).
    public mutating func nextUnit() -> Double {
        let bits = nextUInt64() >> 11
        return Double(bits) / Double(1 << 53)
    }

    public mutating func nextInt(_ upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(upperBound))
    }

    public mutating func shuffle<T>(_ items: inout [T]) {
        guard items.count > 1 else { return }
        var index = items.count - 1
        while index > 0 {
            let swapIndex = nextInt(index + 1)
            items.swapAt(index, swapIndex)
            index -= 1
        }
    }
}

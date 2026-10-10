import Foundation

/// Live tuning. Debug sliders write these fields; the session reads them on the next spawn.
public struct TuningConfig: Equatable {
    /// Divides travel time. Slider 0.50–2.00, default 1.
    public var speedMultiplier: Double
    /// Divides the gap between spawns. Slider 0.50–2.00, default 1.
    public var spawnRateMultiplier: Double
    /// Scales the phase-table jellyfish weight. The other weights are renormalised.
    /// Slider 0–2.00, default 1. A value of 1 uses the phase table as written.
    public var jellyfishMultiplier: Double
    /// Active Big Wave length in seconds, not including the 1.5 s warning. Slider 3–10, default 6.
    public var bigWaveDuration: Double
    /// When false, phase clears do not start a Big Wave. The shipping game leaves this on.
    public var bigWavesEnabled: Bool
    /// If non-empty, spawns take kinds from this list before falling through to the weighted roll.
    /// Lane choice, fairness and travel time still use the normal rules.
    public var scriptedKinds: [ObjectKind]
    /// Demo-only: the third successful spawn is a jellyfish when the rules allow one,
    /// so a short proof run can show the silhouette. Normal games leave this off.
    public var demoSpotlightJellyfish: Bool
    /// Demo-only: the second spawn is a golden shell. Normal games leave this off.
    public var spotlightGoldenShell: Bool
    /// Demo-only: a Big Wave warning begins once the combo reaches 5.
    public var spotlightBigWave: Bool

    public init(
        speedMultiplier: Double = 1,
        spawnRateMultiplier: Double = 1,
        jellyfishMultiplier: Double = 1,
        bigWaveDuration: Double = 6,
        bigWavesEnabled: Bool = true,
        scriptedKinds: [ObjectKind] = [],
        demoSpotlightJellyfish: Bool = false,
        spotlightGoldenShell: Bool = false,
        spotlightBigWave: Bool = false
    ) {
        self.speedMultiplier = speedMultiplier
        self.spawnRateMultiplier = spawnRateMultiplier
        self.jellyfishMultiplier = jellyfishMultiplier
        self.bigWaveDuration = bigWaveDuration
        self.bigWavesEnabled = bigWavesEnabled
        self.scriptedKinds = scriptedKinds
        self.demoSpotlightJellyfish = demoSpotlightJellyfish
        self.spotlightGoldenShell = spotlightGoldenShell
        self.spotlightBigWave = spotlightBigWave
    }

    public func clamped() -> TuningConfig {
        var copy = self
        copy.speedMultiplier = min(2, max(0.5, speedMultiplier))
        copy.spawnRateMultiplier = min(2, max(0.5, spawnRateMultiplier))
        copy.jellyfishMultiplier = min(2, max(0, jellyfishMultiplier))
        copy.bigWaveDuration = min(10, max(3, bigWaveDuration))
        return copy
    }
}

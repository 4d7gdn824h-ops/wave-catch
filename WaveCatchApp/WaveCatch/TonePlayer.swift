import AVFoundation

/// Short original tones. The ambient session follows the hardware mute switch.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat?
    private var started = false

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)
    }

    func start() {
        guard !started, let format else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.play()
            started = true
        } catch {
            started = false
        }
    }

    func play(frequency: Double, duration: Double, volume: Float, pan: Float, sweep: Double = 0) {
        guard started, volume > 0, format != nil else { return }
        guard let buffer = makeBuffer(frequency: frequency, duration: duration, volume: volume, sweep: sweep) else { return }
        player.pan = max(-1, min(1, pan))
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func makeBuffer(frequency: Double, duration: Double, volume: Float, sweep: Double) -> AVAudioPCMBuffer? {
        guard let format else { return nil }
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let samples = buffer.floatChannelData?[0] else { return nil }
        let count = Int(frames)
        for index in 0..<count {
            let t = Double(index) / sampleRate
            let progress = Double(index) / Double(max(count - 1, 1))
            let hz = frequency + sweep * progress
            let envelope = envelope(progress)
            let sample = sin(2 * Double.pi * hz * t)
            samples[index] = Float(sample) * volume * Float(envelope)
        }
        return buffer
    }

    private func envelope(_ progress: Double) -> Double {
        let attack = min(1, progress / 0.08)
        let release = min(1, (1 - progress) / 0.2)
        return max(0, min(attack, release))
    }
}

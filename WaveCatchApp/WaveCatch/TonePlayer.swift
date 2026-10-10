import AVFoundation
import os

/// Plays the original synthesized stems. Music sits under the effects.
/// The ambient session follows the hardware silent switch.
final class TonePlayer {
    private var music: AVAudioPlayer?
    private var wave: AVAudioPlayer?
    private var effects: [AVAudioPlayer] = []
    private var musicOn = true
    private var effectsOn = true
    private var waveMix: Float = 0
    private var waveTarget: Float = 0
    private var ducked = false
    private var duckLeft = 0.0
    private let logProof: Bool
    private let audioLog = Logger(subsystem: "com.example.wavecatch", category: "audio")
    /// Playback gain. Keeps the loop under the wood-block tick and the catch chime.
    private let musicLevel: Float = 0.18
    private let waveLevel: Float = 0.14

    init() {
        logProof = ProcessInfo.processInfo.arguments.contains("-uitest")
            || ProcessInfo.processInfo.arguments.contains("-autoplayDemo")
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    func setMusicOn(_ on: Bool) {
        musicOn = on
        if on {
            startLoops()
        } else {
            music?.pause()
            wave?.pause()
        }
        applyVolumes()
    }

    func setEffectsOn(_ on: Bool) {
        effectsOn = on
    }

    func startLoops() {
        guard musicOn else { return }
        if music == nil {
            music = loop("music-base")
            log("music-base", pan: 0, volume: musicLevel)
        }
        if music?.isPlaying != true {
            music?.play()
        }
        if wave == nil {
            wave = loop("music-wave")
        }
        if wave?.isPlaying != true {
            wave?.play()
        }
        applyVolumes()
    }

    func setWave(_ active: Bool) {
        waveTarget = active ? 1 : 0
        log(active ? "music-wave-on" : "music-wave-off", pan: 0, volume: waveLevel)
    }

    func duck() {
        ducked = true
        duckLeft = 0.85
        applyVolumes()
    }

    func update(dt: Double) {
        let step = Float(min(1, max(0, dt) / 0.5))
        if waveMix < waveTarget {
            waveMix = min(waveTarget, waveMix + step)
        } else if waveMix > waveTarget {
            waveMix = max(waveTarget, waveMix - step)
        }
        if ducked {
            duckLeft -= dt
            if duckLeft <= 0 {
                ducked = false
            }
        }
        applyVolumes()
        effects.removeAll { !$0.isPlaying }
    }

    func play(_ name: String, pan: Float, volume: Float) {
        guard effectsOn, volume > 0 else { return }
        guard let url = locate(name, ext: "m4a") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.pan = max(-1, min(1, pan))
        player.volume = volume
        player.prepareToPlay()
        player.play()
        effects.append(player)
        log(name, pan: player.pan, volume: volume)
    }

    private func loop(_ name: String) -> AVAudioPlayer? {
        guard let url = locate(name, ext: "m4a") else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = -1
        player?.prepareToPlay()
        return player
    }

    private func applyVolumes() {
        let duckScale: Float = ducked ? 0.7 : 1
        let base: Float = musicOn ? musicLevel * duckScale : 0
        music?.volume = base * (1 - 0.15 * waveMix)
        wave?.volume = (musicOn ? waveLevel * duckScale : 0) * waveMix
    }

    private func locate(_ name: String, ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        return Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Audio")
    }

    private func log(_ name: String, pan: Float, volume: Float) {
        guard logProof else { return }
        let line = String(format: "WCAUDIO %.3f %@ %.2f %.2f", Date().timeIntervalSince1970, name, pan, volume)
        audioLog.notice("\(line, privacy: .public)")
    }
}

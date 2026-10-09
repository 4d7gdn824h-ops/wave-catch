import AVFoundation
import CoreMedia
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("usage: compress-proof input.mp4 output.mp4\n", stderr)
    exit(2)
}

let input = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let asset = AVURLAsset(url: input)
let seconds = CMTimeGetSeconds(asset.duration)
guard seconds.isFinite, seconds > 0.2 else {
    fputs("recording has no duration\n", stderr)
    exit(1)
}

func export(preset: String) -> Bool {
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return false }
    try? FileManager.default.removeItem(at: output)
    session.outputURL = output
    session.outputFileType = .mp4
    session.shouldOptimizeForNetworkUse = true
    let length = min(30, seconds)
    let start = max(0, seconds - length)
    session.timeRange = CMTimeRange(
        start: CMTime(seconds: start, preferredTimescale: 600),
        duration: CMTime(seconds: length, preferredTimescale: 600)
    )
    let gate = DispatchSemaphore(value: 0)
    session.exportAsynchronously { gate.signal() }
    gate.wait()
    if session.status != .completed {
        let message = session.error?.localizedDescription ?? "export failed"
        fputs("\(preset): \(message)\n", stderr)
        return false
    }
    return true
}

if !export(preset: AVAssetExportPreset640x480) && !export(preset: AVAssetExportPresetLowQuality) {
    exit(1)
}

let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.intValue ?? 0
if size > 15_000_000 {
    fputs("proof video is \(size) bytes\n", stderr)
    exit(1)
}
print("proof video \(size) bytes")

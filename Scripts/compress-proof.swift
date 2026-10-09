import AVFoundation
import CoreMedia
import CoreVideo
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

let keep = seconds > 48 ? 45.0 : seconds
let outWidth = 1280
let outHeight = 590

guard let track = asset.tracks(withMediaType: .video).first else {
    fputs("recording has no video track\n", stderr)
    exit(1)
}

func fittedTransform(for track: AVAssetTrack) -> CGAffineTransform {
    let natural = track.naturalSize
    let oriented = CGRect(origin: .zero, size: natural).applying(track.preferredTransform)
    let sourceWidth = abs(oriented.width)
    let sourceHeight = abs(oriented.height)
    let scale = min(CGFloat(outWidth) / max(sourceWidth, 1), CGFloat(outHeight) / max(sourceHeight, 1))
    var transform = track.preferredTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    let scaled = CGRect(origin: .zero, size: natural).applying(transform)
    let dx = (CGFloat(outWidth) - scaled.width) / 2 - scaled.origin.x
    let dy = (CGFloat(outHeight) - scaled.height) / 2 - scaled.origin.y
    transform = transform.concatenating(CGAffineTransform(translationX: dx, y: dy))
    return transform
}

func export(bitRate: Int) -> Bool {
    try? FileManager.default.removeItem(at: output)
    let composition = AVMutableVideoComposition()
    composition.renderSize = CGSize(width: outWidth, height: outHeight)
    composition.frameDuration = CMTime(value: 1, timescale: 30)
    let instruction = AVMutableVideoCompositionInstruction()
    let range = CMTimeRange(start: .zero, duration: CMTime(seconds: keep, preferredTimescale: 600))
    instruction.timeRange = range
    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layer.setTransform(fittedTransform(for: track), at: .zero)
    instruction.layerInstructions = [layer]
    composition.instructions = [instruction]

    let reader: AVAssetReader
    do {
        reader = try AVAssetReader(asset: asset)
    } catch {
        fputs("reader: \(error.localizedDescription)\n", stderr)
        return false
    }
    reader.timeRange = range
    let readerOutput = AVAssetReaderVideoCompositionOutput(
        videoTracks: [track],
        videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    )
    readerOutput.videoComposition = composition
    readerOutput.alwaysCopiesSampleData = false
    guard reader.canAdd(readerOutput) else {
        fputs("reader cannot add the composition output\n", stderr)
        return false
    }
    reader.add(readerOutput)

    let writer: AVAssetWriter
    do {
        writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
    } catch {
        fputs("writer: \(error.localizedDescription)\n", stderr)
        return false
    }
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: outWidth,
        AVVideoHeightKey: outHeight,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: bitRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 30,
            AVVideoExpectedSourceFrameRateKey: 30
        ]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    guard writer.canAdd(input) else {
        fputs("writer cannot add the video input\n", stderr)
        return false
    }
    writer.add(input)
    guard reader.startReading() else {
        fputs("reader start: \(reader.error?.localizedDescription ?? "failed")\n", stderr)
        return false
    }
    guard writer.startWriting() else {
        fputs("writer start: \(writer.error?.localizedDescription ?? "failed")\n", stderr)
        return false
    }
    writer.startSession(atSourceTime: .zero)

    let state = NSLock()
    var finished = false
    func markFinished() {
        state.lock()
        finished = true
        state.unlock()
    }
    func isFinished() -> Bool {
        state.lock()
        defer { state.unlock() }
        return finished
    }

    let queue = DispatchQueue(label: "compress-proof")
    input.requestMediaDataWhenReady(on: queue) {
        while input.isReadyForMoreMediaData {
            if reader.status == .failed {
                input.markAsFinished()
                writer.cancelWriting()
                markFinished()
                return
            }
            guard let sample = readerOutput.copyNextSampleBuffer() else {
                input.markAsFinished()
                writer.finishWriting { markFinished() }
                return
            }
            if !input.append(sample) {
                input.markAsFinished()
                writer.cancelWriting()
                markFinished()
                return
            }
        }
    }
    let started = Date()
    while !isFinished() {
        if Date().timeIntervalSince(started) > 180 {
            fputs("encode timed out\n", stderr)
            return false
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }
    if writer.status != .completed {
        fputs("encode \(bitRate): \(writer.error?.localizedDescription ?? "failed")\n", stderr)
        return false
    }
    return true
}

if !export(bitRate: 2_200_000) {
    exit(1)
}

func fileSize(_ url: URL) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
}

var size = fileSize(output)
if size > 15_000_000 {
    fputs("retrying at a lower bitrate (\(size) bytes)\n", stderr)
    if !export(bitRate: 1_500_000) {
        exit(1)
    }
    size = fileSize(output)
}
if size > 15_000_000 || size == 0 {
    fputs("proof video is \(size) bytes\n", stderr)
    exit(1)
}

let written = AVURLAsset(url: output)
let duration = CMTimeGetSeconds(written.duration)
print(String(format: "proof video %dx%d duration %.1fs %d bytes", outWidth, outHeight, duration, size))

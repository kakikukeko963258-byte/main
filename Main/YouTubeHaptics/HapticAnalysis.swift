import AVFoundation
import CoreHaptics
import Foundation

struct HapticMedia {
    struct Segment {
        let start: Double
        let pattern: CHHapticPattern
        let eventCount: Int
        let transientCount: Int
    }
    let directory: URL
    let asset: AVAsset
    let duration: Double
    let segments: [Segment]
}

enum HapticMediaError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

enum HapticAnalysis {
    // Decode to bounded 20-second mono PCM chunks, retaining only haptic events.
    // Keeping conversion in bounded chunks prevents long movies from allocating an
    // audio-sized buffer while preserving a continuous playback timeline.
    static func analyze(_ asset: AVAsset, directory: URL, duration: Double,
                        progress: @escaping @Sendable (String) -> Void) async throws -> [HapticMedia.Segment] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw HapticMediaError.message("この動画には音声トラックがありません。")
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 22050,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? HapticMediaError.message("音声を解析できません。") }
        defer { reader.cancelReading() }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)!
        let capacity = 22050 * 20
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity))!
        var filled = 0
        var start = 0.0
        var result: [HapticMedia.Segment] = []
        let chunkURL = directory.appendingPathComponent("analysis.caf")
        func flush() throws {
            guard filled > 0 else { return }
            buffer.frameLength = AVAudioFrameCount(filled)
            do {
                let file = try AVAudioFile(forWriting: chunkURL, settings: format.settings)
                try file.write(from: buffer)
            }
            let conversion = try HapticConverter.convert(audioURL: chunkURL)
            result.append(.init(start: start, pattern: conversion.pattern,
                                eventCount: conversion.eventCount, transientCount: conversion.transientCount))
            start += Double(filled) / 22050
            filled = 0
            progress("音声を解析して振動に変換中… \(Int(min(100, start / duration * 100)))%")
        }
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let count = CMSampleBufferGetNumSamples(sample)
            var values = [Float](repeating: 0, count: count)
            let status = values.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: bytes.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { throw HapticMediaError.message("音声データを読み取れません。") }
            var offset = 0
            while offset < count {
                let length = min(capacity - filled, count - offset)
                values.withUnsafeBufferPointer { source in
                    buffer.floatChannelData![0].advanced(by: filled).update(from: source.baseAddress!.advanced(by: offset), count: length)
                }
                filled += length
                offset += length
                if filled == capacity { try flush() }
            }
        }
        guard reader.status == .completed else { throw reader.error ?? HapticMediaError.message("音声変換が中断されました。") }
        try flush()
        try? FileManager.default.removeItem(at: chunkURL)
        guard !result.isEmpty else { throw HapticMediaError.message("変換できる音声がありません。") }
        return result
    }
}

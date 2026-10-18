import Foundation
import AVFoundation
import CoreHaptics

@main
struct HapticChecks {
    static func main() async throws {
        for url in ["https://youtu.be/abcdefgh_-1?t=20", "https://www.youtube.com/watch?v=abcdefgh_-1&list=x", "https://m.youtube.com/shorts/abcdefgh_-1", "https://youtube.com/live/abcdefgh_-1"] {
            precondition(YouTubeLink.videoID(url) == "abcdefgh_-1")
        }
        for url in ["file:///watch?v=abcdefgh_-1", "https://youtube.com.evil.test/watch?v=abcdefgh_-1", "https://youtube.com/playlist?list=abcdefgh_-1", "https://youtu.be/short", "https://example.com/abcdefgh_-1", ""] {
            precondition(YouTubeLink.videoID(url) == nil)
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050)!
        buffer.frameLength = 22050
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            for second in 0..<41 {
                for frame in 0..<22050 {
                    buffer.floatChannelData![0][frame] = second < 20 ? 0 : Float(sin(Double(frame) / 22050 * 440 * 2 * .pi)) * 0.5
                }
                try file.write(from: buffer)
            }
        }
        let asset = AVURLAsset(url: url)
        let segments = try await HapticAnalysis.analyze(asset, directory: directory, duration: 41, progress: { _ in })
        precondition(segments.count == 3, "Long media must not be truncated")
        precondition(segments.map(\.start) == [0, 20, 40])
        precondition(segments[0].pattern.duration == 0, "Silence must not produce vibration")
        precondition(segments[1].pattern.duration > 19)
        precondition(segments[2].pattern.duration > 0.8, "Final partial segment must be retained")
        print("PASS: YouTube URL validation, silent audio, 20-second boundaries, final chunk, AHAPpy conversion")
    }
}

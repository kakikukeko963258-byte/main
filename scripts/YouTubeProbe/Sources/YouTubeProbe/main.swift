import Foundation
import YouTubeKit

@main
struct Probe {
    static func main() async throws {
        let streams = try await YouTube(videoID: "jNQXAC9IVRw", methods: [.local]).streams
        guard let stream = streams.filter({ $0.isNativelyPlayable && $0.fileExtension == .mp4 && $0.includesVideoTrack }).lowestResolutionStream() else {
            throw NSError(domain: "probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "No native MP4 stream"])
        }
        var request = URLRequest(url: stream.url)
        request.setValue("bytes=0-4095", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        let (temporary, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw NSError(domain: "probe", code: status, userInfo: [NSLocalizedDescriptionKey: "Media HTTP \(status)"])
        }
        print("PASS: local YouTube extraction returned \(streams.count) streams; media HTTP \(status). Runner region/IP only; device verification still required.")
    }
}

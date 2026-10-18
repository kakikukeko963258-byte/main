import Foundation
import YouTubeKit

@main
struct Probe {
    static func main() async {
        do { try await probe() }
        catch {
            print("UNVERIFIED: YouTube extraction failed: \(error)")
            var request = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 20
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["videoId": "jNQXAC9IVRw", "context": ["client": ["clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple", "deviceModel": "RealityDevice17,1", "osName": "visionOS", "osVersion": "26.5.23O471"]]])
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["playabilityStatus"] as? [String: Any] {
                print("Runner network diagnostic: \(status["status"] ?? "unknown"): \(status["reason"] ?? "no reason")")
            }
            exit(1)
        }
    }
    static func probe() async throws {
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

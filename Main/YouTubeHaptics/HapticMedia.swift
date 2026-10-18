import AVFoundation
import CoreHaptics
import Foundation
import YouTubeKit

enum HapticMediaBuilder {
    static func prepare(id: String, progress: @escaping @Sendable (String) -> Void) async throws -> HapticMedia {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("youtube-haptics-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            progress("YouTubeから動画情報を取得中…")
            let streams = try await YouTube(videoID: id, methods: [.local]).streams
            try Task.checkCancellation()
            let playable = streams.filter { $0.isNativelyPlayable && $0.fileExtension == .mp4 }
            let combinedStreams = playable.filterVideoAndAudio()
            // The user values a short wait over a large picture. Start with the
            // smallest phone-friendly progressive stream and fall back to the
            // smallest available resolution when 240p is not offered.
            let combined = combinedStreams.filter(byResolution: { ($0 ?? Int.max) <= 240 }).lowestResolutionStream()
                ?? combinedStreams.lowestResolutionStream()
            let asset: AVAsset
            if let stream = combined {
                progress("動画と音声を取得中…")
                let url = try await download(stream.url, to: directory.appendingPathComponent("video.mp4"))
                asset = AVURLAsset(url: url)
            } else {
                let videoStreams = playable.filterVideoOnly()
                guard let video = videoStreams.filter(byResolution: { ($0 ?? Int.max) <= 240 }).lowestResolutionStream()
                        ?? videoStreams.lowestResolutionStream(),
                      let audio = streams.filterAudioOnly().filter({ $0.fileExtension == .m4a }).lowestAudioBitrateStream() else {
                    throw HapticMediaError.message("この動画の再生可能な映像・音声を取得できません。公開動画のリンクで再試行してください。ライブ配信・非公開・年齢制限などには対応していません。")
                }
                progress("映像を取得中…")
                let videoURL = try await download(video.url, to: directory.appendingPathComponent("video.mp4"))
                progress("音声を取得中…")
                let audioURL = try await download(audio.url, to: directory.appendingPathComponent("audio.m4a"))
                let composition = AVMutableComposition()
                let sources: [(URL, AVMediaType)] = [(videoURL, .video), (audioURL, .audio)]
                for (url, type) in sources {
                    let source = AVURLAsset(url: url)
                    let tracks = try await source.loadTracks(withMediaType: type)
                    guard let track = tracks.first,
                          let target = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                        throw HapticMediaError.message("動画のトラックを読み込めません。")
                    }
                    let range = try await track.load(.timeRange)
                    try target.insertTimeRange(range, of: track, at: CMTime.zero)
                    if type == .video { target.preferredTransform = try await track.load(.preferredTransform) }
                }
                asset = composition
            }
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw HapticMediaError.message("動画の長さを取得できません。") }
            progress("AHAPpyで振動に変換中…")
            let segments = try await HapticAnalysis.analyze(asset, directory: directory, duration: duration, progress: progress)
            try Task.checkCancellation()
            return HapticMedia(directory: directory, asset: asset, duration: duration, segments: segments)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func download(_ source: URL, to destination: URL) async throws -> URL {
        var request = URLRequest(url: source)
        request.timeoutInterval = 90
        let limiter = DownloadLimit()
        let (temporary, response) = try await URLSession.shared.download(for: request, delegate: limiter)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HapticMediaError.message("YouTubeの取得に失敗しました。リンクを再取得してください。")
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

}

private final class DownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Bound disk consumption, including responses with unknown Content-Length.
        if max(totalBytesWritten, totalBytesExpectedToWrite) > 1_073_741_824 { downloadTask.cancel() }
    }
}

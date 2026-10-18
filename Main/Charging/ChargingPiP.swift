import AVKit
import AVFoundation
import SwiftUI

/// A live sample-buffer video, explicitly started by the user. Inspired by
/// MiniWatts' Apache-2.0 PiP approach; no audio track or silent audio loop.
@MainActor final class ChargingPiP: NSObject, ObservableObject {
    static let shared = ChargingPiP()
    @Published private(set) var status = "停止中"
    @Published private(set) var running = false
    @Published private(set) var starting = false
    @Published private(set) var possible = false
    let supported = AVPictureInPictureController.isPictureInPictureSupported()
    let layer = AVSampleBufferDisplayLayer()
    private var controller: AVPictureInPictureController?
    private var proxy: Delegate?
    private var observation: NSKeyValueObservation?
    private var interruption: NSObjectProtocol?
    private var startup: Task<Void, Never>?
    private var pool: CVPixelBufferPool?
    private var painted = false
    private var latest = ChargeState.empty
    private var trace: [ChargeSample] = []
    private var cadence = 0.0

    override init() {
        super.init()
        layer.videoGravity = .resizeAspect
        if !supported { status = "この端末ではPiPを利用できません" }
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main) { [weak self] note in
            guard (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.stop() }
        }
    }
    func prepare() {
        guard supported, controller == nil else { return }
        let proxy = Delegate(owner: self)
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: layer, playbackDelegate: proxy)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = proxy
        controller.requiresLinearPlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        self.proxy = proxy; self.controller = controller
        observation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            Task { @MainActor in self?.possible = possible }
        }
        render()
    }
    func update(_ state: ChargeState, samples: [ChargeSample], hertz: Double) {
        latest = state; cadence = hertz
        // The video graph needs at most the most recent minute.
        trace = Array(samples.suffix(600))
        if running || starting || !painted { render() }
    }
    func start() {
        guard supported, !running, !starting else { return }
        prepare()
        do {
            let session = AVAudioSession.sharedInstance()
            // Preserve the existing listening player's playback category/mode.
            let mode: AVAudioSession.Mode = session.category == .playback ? session.mode : .default
            try session.setCategory(.playback, mode: mode, options: session.categoryOptions.union(.mixWithOthers))
            try session.setActive(true)
        } catch { status = "音声セッション: \(error.localizedDescription)"; return }
        starting = true; status = "PiPを開始中"
        ChargingMonitor.shared.setPiPActive(true)
        startup = Task { [weak self] in
            guard let self else { return }
            for _ in 0..<60 {
                guard starting, !Task.isCancelled else { return }
                render()
                if controller?.isPictureInPicturePossible == true {
                    controller?.startPictureInPicture()
                    break
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            try? await Task.sleep(for: .seconds(6))
            if starting { failed("iOSがPiPの開始を許可しませんでした。画面を開いたまま再試行してください。") }
        }
    }
    func stop() {
        startup?.cancel(); startup = nil
        if running { controller?.stopPictureInPicture() }
        else { stopped() }
    }
    private func started() {
        startup?.cancel(); startup = nil
        starting = false; running = true; status = "PiPで測定中"
        ChargingMonitor.shared.setPiPActive(true)
    }
    private func stopped() {
        starting = false; running = false; status = "停止中"
        ChargingMonitor.shared.setPiPActive(false)
        // Do not deactivate the process-wide audio session: main's listening
        // player may still be using it. No audio is emitted by this controller.
    }
    private func failed(_ message: String) {
        stopped(); status = "PiP: \(message)"
    }
    private func render() {
        let width = 480, height = 270
        if pool == nil {
            let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
            CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
        }
        guard let pool else { return }
        var pixel: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixel) == kCVReturnSuccess, let pixel else { return }
        CVPixelBufferLockBaseAddress(pixel, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            CVPixelBufferUnlockBaseAddress(pixel, []); return
        }
        // UIKit text uses a top-left origin; draw directly into pooled pixels.
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        func text(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, color: UIColor = .white) {
            (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: color])
        }
        text("main 充電モニター", x: 20, y: 12, size: 17, color: .systemGreen)
        text(latest.percentText, x: 370, y: 12, size: 20)
        text(latest.powerText, x: 20, y: 41, size: 40)
        text(latest.temperature.map { String(format: "%.1f °C", $0) } ?? "温度 —", x: 320, y: 55, size: 21)
        text(latest.watts == nil ? "入力電力 取得不可" : "実測由来・17e未校正", x: 20, y: 91, size: 13, color: .lightGray)
        let graph = CGRect(x: 20, y: 121, width: 440, height: 75)
        UIColor.darkGray.setStroke(); context.stroke(graph)
        let now = latest.date
        let values = trace.filter { now.timeIntervalSince($0.date) <= 60 }
        let ceiling = max(5, values.compactMap(\.watts).max() ?? 5)
        context.setStrokeColor(UIColor.systemGreen.cgColor); context.setLineWidth(2)
        var prior: ChargeSample?
        var hasPath = false
        for sample in values {
            guard let watts = sample.watts else { prior = nil; continue }
            let x = graph.minX + graph.width * CGFloat(1 - now.timeIntervalSince(sample.date) / 60)
            let y = graph.maxY - graph.height * CGFloat(watts / ceiling)
            if let p = prior, sample.session == p.session, sample.date.timeIntervalSince(p.date) < 2 {
                context.addLine(to: CGPoint(x: x, y: y))
            } else { context.move(to: CGPoint(x: x, y: y)) }
            prior = sample; hasPath = true
        }
        if hasPath { context.strokePath() }
        let eta = latest.eta100.map { $0.formatted(date: .omitted, time: .shortened) } ?? "—"
        text("100% 推定 \(eta)", x: 20, y: 204, size: 16)
        text(String(format: "実取得 %.1f Hz", cadence), x: 290, y: 204, size: 15, color: .lightGray)
        text(latest.isStale(at: .now) ? "更新停止・古い測定値" : "測定 \(latest.date.formatted(date: .omitted, time: .standard))", x: 20, y: 237, size: 13, color: latest.paused ? .systemOrange : .lightGray)
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format) == noErr,
              let format else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: format,
            sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let entry = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(entry, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        let renderer = layer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        if renderer.isReadyForMoreMediaData { renderer.enqueue(sample); painted = true }
    }
    @MainActor private final class Delegate: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
        weak var owner: ChargingPiP?
        init(owner: ChargingPiP) { self.owner = owner }
        nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) { Task { @MainActor in self.owner?.started() } }
        nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) { Task { @MainActor in self.owner?.stopped() } }
        nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
            let message = error.localizedDescription
            Task { @MainActor in self.owner?.failed(message) }
        }
        nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) { completionHandler(true) }
        nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) { if !playing { Task { @MainActor in self.owner?.stop() } } }
        nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange { CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity) }
        nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool { false }
        nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
        nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) { completionHandler() }
        nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ controller: AVPictureInPictureController) -> Bool { false }
    }
}

struct ChargingPiPStage: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = Host()
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(ChargingPiP.shared.layer)
        ChargingPiP.shared.prepare()
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    final class Host: UIView {
        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin(); CATransaction.setDisableActions(true)
            layer.sublayers?.forEach { $0.frame = bounds }
            CATransaction.commit()
        }
    }
}

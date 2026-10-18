import SwiftUI
import AVKit
import CoreHaptics

@MainActor
final class YouTubeHapticsModel: ObservableObject {
    @Published var link = ""
    @Published var status = "YouTubeリンクを入力してください"
    @Published var busy = false
    @Published var ready = false
    @Published var playing = false
    @Published var position = 0.0
    @Published var duration = 1.0
    @Published var hapticsEnabled = true
    @Published var strength: Float = 1
    @Published var error: String?
    let player = AVPlayer()
    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var media: HapticMedia?
    private var engine: CHHapticEngine?
    private var hapticPlayer: CHHapticAdvancedPatternPlayer?
    private var segmentIndex: Int?
    private var anchorVideo = 0.0
    private var anchorHost = 0.0
    private var timer: Timer?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var seeking = false
    private var seekID = UUID()
    private var interruption: NSObjectProtocol?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause() }
        }
    }

    deinit {
        timer?.invalidate()
        task?.cancel()
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
    }

    func load() {
        guard let id = YouTubeLink.videoID(link) else {
            error = "有効なYouTube動画のリンクを入力してください。watch・youtu.be・Shortsに対応しています。"
            return
        }
        clear()
        busy = true
        error = nil
        let token = UUID()
        requestID = token
        task = Task {
            let worker = Task.detached(priority: .userInitiated) {
                try await HapticMediaBuilder.prepare(id: id) { [weak self] message in
                    Task { @MainActor in
                        guard self?.requestID == token else { return }
                        self?.status = message
                    }
                }
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, requestID == token else {
                    try? FileManager.default.removeItem(at: result.directory)
                    return
                }
                media = result
                duration = result.duration
                player.replaceCurrentItem(with: AVPlayerItem(asset: result.asset))
                ready = true
                busy = false
                status = "変換完了 · 再生すると動画と振動が始まります"
            } catch {
                guard requestID == token else { return }
                busy = false
                if Task.isCancelled { status = "キャンセルしました" }
                else {
                    status = "取得・変換に失敗しました"
                    self.error = "\(error.localizedDescription)\nYouTube側の変更や動画の公開条件によって取得できない場合があります。通信を確認して再試行してください。取得上限は映像・音声それぞれ1GBです。"
                }
            }
        }
    }

    func pause() {
        seekID = UUID()
        player.pause()
        playing = false
        stopHaptics()
    }

    func toggle() {
        if playing { pause(); return }
        guard ready else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
            if position >= duration - 0.1 { seek(to: 0, resume: true) }
            else { playing = true; player.play() }
        } catch { self.error = error.localizedDescription }
    }

    func seek(to time: Double, resume: Bool? = nil) {
        guard ready else { return }
        let shouldPlay = resume ?? playing
        seeking = true
        pause()
        let target = min(max(0, time), duration)
        position = target
        let token = requestID
        let seekToken = UUID()
        seekID = seekToken
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            Task { @MainActor in
                guard let self, self.requestID == token else { return }
                self.seeking = false
                if finished && shouldPlay && self.seekID == seekToken { self.playing = true; self.player.play() }
            }
        }
    }

    func clear() {
        requestID = UUID()
        task?.cancel()
        task = nil
        pause()
        player.replaceCurrentItem(with: nil)
        if let media { try? FileManager.default.removeItem(at: media.directory) }
        media = nil
        engine?.stop()
        engine = nil
        ready = false
        busy = false
        seeking = false
        position = 0
        duration = 1
        status = "YouTubeリンクを入力してください"
    }

    func settingsChanged() { stopHaptics() }

    private func stopHaptics() {
        try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
        hapticPlayer = nil
        segmentIndex = nil
    }

    private func tick() {
        guard ready, !seeking else { return }
        let time = player.currentTime().seconds
        guard time.isFinite else { return }
        position = min(duration, max(0, time))
        if let failure = player.currentItem?.error {
            pause(); error = failure.localizedDescription; ready = false; return
        }
        guard player.timeControlStatus == .playing, playing else {
            stopHaptics()
            if position >= duration - 0.1 { playing = false }
            return
        }
        guard supportsHaptics, hapticsEnabled, let media else { stopHaptics(); return }
        guard let index = media.segments.lastIndex(where: { $0.start <= time }) else { return }
        let drift = abs((time - anchorVideo) - (CACurrentMediaTime() - anchorHost))
        guard segmentIndex != index || drift > 0.12 else { return }
        do {
            stopHaptics()
            if engine == nil {
                let newEngine = try CHHapticEngine()
                newEngine.playsHapticsOnly = true
                newEngine.resetHandler = { [weak self] in Task { @MainActor in self?.stopHaptics() } }
                newEngine.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.stopHaptics() } }
                engine = newEngine
            }
            try engine?.start()
            let segment = media.segments[index]
            // Silence-only segments need no player and must not be treated as errors.
            if segment.pattern.duration > time - segment.start {
                let hp = try engine!.makeAdvancedPlayer(with: segment.pattern)
                try hp.seek(toOffset: max(0, time - segment.start))
                try hp.sendParameters([CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: strength, relativeTime: 0)], atTime: CHHapticTimeImmediate)
                try hp.start(atTime: CHHapticTimeImmediate)
                hapticPlayer = hp
            }
            segmentIndex = index
            anchorVideo = time
            anchorHost = CACurrentMediaTime()
        } catch {
            stopHaptics()
            hapticsEnabled = false
            self.error = "振動を開始できませんでした。動画の再生は続けられます。\n\(error.localizedDescription)"
        }
    }
}

private struct HapticVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        (view.layer as? AVPlayerLayer)?.player = player
        (view.layer as? AVPlayerLayer)?.videoGravity = .resizeAspect
        return view
    }
    func updateUIView(_ uiView: Surface, context: Context) {}
}

struct YouTubeHapticsView: View {
    let onHome: () -> Void
    @StateObject private var model = YouTubeHapticsModel()
    @Environment(\.scenePhase) private var phase
    @State private var scrub = 0.0
    @State private var scrubbing = false
    @State private var resumeAfterScrub = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("動画を、振動でも楽しむ").font(.title2.bold())
                    Text("リンクを入力 → 取得 → AHAPpyで変換 → 同期再生").font(.subheadline).foregroundStyle(.secondary)
                    TextField("https://www.youtube.com/watch?v=…", text: $model.link)
                        .textFieldStyle(.roundedBorder).keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().accessibilityIdentifier("haptics-link")
                    HStack {
                        Button("取得して振動に変換") { model.load() }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.link.isEmpty)
                            .accessibilityIdentifier("haptics-convert")
                        if model.busy { Button("キャンセル") { model.clear() } }
                    }
                    if model.busy { ProgressView() }
                    Text(model.status).font(.subheadline).accessibilityIdentifier("haptics-status")
                    if model.ready {
                        HapticVideoSurface(player: model.player).aspectRatio(16 / 9, contentMode: .fit)
                            .background(.black).clipShape(RoundedRectangle(cornerRadius: 16))
                        Slider(value: Binding(get: { scrubbing ? scrub : model.position }, set: { scrub = $0 }), in: 0...max(1, model.duration)) { editing in
                            if editing {
                                scrub = model.position; resumeAfterScrub = model.playing
                                scrubbing = true; model.pause()
                            } else {
                                scrubbing = false; model.seek(to: scrub, resume: resumeAfterScrub)
                            }
                        }.accessibilityLabel("再生位置")
                        HStack {
                            Text("\(clock(model.position)) / \(clock(model.duration))").monospacedDigit()
                            Spacer()
                            Button { model.seek(to: model.position - 10) } label: { Image(systemName: "gobackward.10") }
                            Button { model.toggle() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill") }
                                .accessibilityLabel(model.playing ? "一時停止" : "再生")
                            Button { model.seek(to: model.position + 10) } label: { Image(systemName: "goforward.10") }
                        }.font(.title3).buttonStyle(.bordered)
                        Toggle("振動", isOn: $model.hapticsEnabled).disabled(!model.supportsHaptics)
                        HStack {
                            Text("振動の強さ")
                            Slider(value: $model.strength, in: 0...1).accessibilityLabel("振動の強さ")
                        }
                        Button("動画と変換データを削除") { model.clear() }.buttonStyle(.bordered)
                    }
                    if !model.supportsHaptics { Text("この端末ではCore Hapticsの振動を利用できません。").foregroundStyle(.orange) }
                    Text("公開動画のリンクを指定してください。ライブ配信・非公開・年齢制限など、取得できない動画があります。変換データはこの画面を閉じると削除されます。映像・音声は各1GBまで。画面を閉じる／バックグラウンドへ移ると再生を停止します。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("音声解析: AHAPpy · 動画取得: YouTubeKit").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("YouTube × 振動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("ホームへ戻る") { model.clear(); onHome() } } }
        }
        .onDisappear { model.clear() }
        .onChange(of: phase) { value in if value != .active { model.pause() } }
        .onChange(of: model.hapticsEnabled) { _ in model.settingsChanged() }
        .onChange(of: model.strength) { _ in model.settingsChanged() }
        .alert("YouTube × 振動", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private func clock(_ time: Double) -> String {
        let seconds = Int(max(0, time))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

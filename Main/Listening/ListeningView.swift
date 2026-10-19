import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

struct ListeningWordTiming: Decodable {
    let start: Double
    let end: Double
    let location: Int
    let length: Int
}

struct ListeningTrack: Decodable, Identifiable {
    let id: Int
    let title: String
    let sections: [String]
    var text: String { sections.joined(separator: "\n\n") }
}

enum RepeatMode: String, CaseIterable {
    case off = "オフ", selection = "選択範囲", all = "全体"
}

final class ListeningAudioModel: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = ListeningAudioModel()
    @Published var tracks: [ListeningTrack] = []
    @Published var selected = 0
    @Published var chapter = -1
    @Published var playing = false
    @Published var generating = false
    @Published var message = "写真を選んで再生してください"
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published private(set) var activeWord: Int?
    private var wordTimelines: [String: [ListeningWordTiming]] = [:]
    var currentWords: [ListeningWordTiming] {
        guard let track = track else { return [] }
        let scope = chapter < 0 ? "full" : "chapter-\(chapter + 1)"
        return wordTimelines["photo-\(track.id)-\(scope)"] ?? []
    }
    var readingText: String {
        guard let track = track else { return "" }
        return chapter < 0 ? track.text : track.sections[chapter]
    }
    @Published var speed: Float = 1 { didSet { player?.rate = speed; nowPlaying() } }
    @Published var repeatMode: RepeatMode = .selection {
        didSet { player?.numberOfLoops = repeatMode == .selection ? -1 : 0 }
    }
    @Published var deadline: Date?
    @Published var remaining = 0
    private var player: AVAudioPlayer?
    private let synth = AVSpeechSynthesizer()
    private var file: AVAudioFile?
    private var tick: Timer?
    private var renderError: Error?
    private var generationTimedOut = false
    private var interruption: NSObjectProtocol?
    private var routeChange: NSObjectProtocol?
    var track: ListeningTrack? { tracks.indices.contains(selected) ? tracks[selected] : nil }

    override init() {
        super.init()
        do {
            guard let url = Bundle.main.url(forResource: "tracks", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
            tracks = try JSONDecoder().decode([ListeningTrack].self, from: Data(contentsOf: url))
            if let timings = Bundle.main.url(forResource: "word-timings", withExtension: "json") {
                wordTimelines = try JSONDecoder().decode([String: [ListeningWordTiming]].self, from: Data(contentsOf: timings))
            }
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch { message = "初期化できません: \(error.localizedDescription)" }
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.update() }
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { self?.pause() }
        }
        routeChange = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
        }
        MPRemoteCommandCenter.shared().playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.play() }; return .success
        }
        MPRemoteCommandCenter.shared().pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pause() }; return .success
        }
    }

    func choose(_ index: Int) {
        guard !generating, index != selected else { return }
        pause(); player = nil; selected = index; chapter = -1; position = 0; duration = 0
        activeWord = nil
        message = "写真\(index + 1)を選択しました"
    }
    func chooseChapter(_ index: Int) {
        guard !generating, let track = track,
              index == -1 || track.sections.indices.contains(index), index != chapter else { return }
        pause(); player = nil; chapter = index; position = 0; duration = 0
        activeWord = nil
        message = index == -1 ? "写真全体を選択しました" : "第\(index + 1)章を選択しました"
    }
    func play() {
        guard !generating, let track = track else { return }
        if let player = player {
            if let deadline = deadline, deadline <= Date() { self.deadline = nil; remaining = 0 }
            do { try AVAudioSession.sharedInstance().setActive(true) }
            catch { message = error.localizedDescription; return }
            if player.currentTime >= player.duration { player.currentTime = 0 }
            playing = player.play(); nowPlaying(); return
        }
        let scope = chapter < 0 ? "full" : "chapter-\(chapter + 1)"
        let bundledName = "photo-\(track.id)-\(scope)"
        if let bundled = Bundle.main.url(forResource: bundledName, withExtension: "mp3") {
            load(bundled)
            return
        }
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("photo-\(track.id)-\(scope)-v2.caf")
        if FileManager.default.fileExists(atPath: url.path) { load(url); return }
        generating = true; message = "写真\(track.id)の音声を作成中…初回のみ時間がかかります"
        generationTimedOut = false
        file = nil; renderError = nil
        let utterance = AVSpeechUtterance(string: chapter < 0 ? track.text : track.sections[chapter])
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synth.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            // Consume buffers before returning from Apple's callback.
            let consume = {
                guard let self = self else { return }
                if pcm.frameLength == 0 {
                    self.file = nil; self.generating = false
                    if let error = self.renderError {
                        try? FileManager.default.removeItem(at: url)
                        self.message = "音声作成に失敗: \(error.localizedDescription)"
                    } else { self.load(url) }
                } else if self.renderError == nil {
                    do {
                        if self.file == nil { self.file = try AVAudioFile(forWriting: url, settings: pcm.format.settings) }
                        try self.file?.write(from: pcm)
                    } catch { self.renderError = error }
                }
            }
            if Thread.isMainThread { consume() } else { DispatchQueue.main.sync(execute: consume) }
        }
    }
    private func load(_ url: URL) {
        do {
            let result = try AVAudioPlayer(contentsOf: url)
            guard result.duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            player = result; result.delegate = self; result.enableRate = true
            result.rate = speed; result.numberOfLoops = repeatMode == .selection ? -1 : 0
            duration = result.duration; message = "音声の準備ができました"
            if generationTimedOut { message = "スリープタイマーで停止しました"; generationTimedOut = false }
            else { play() }
        } catch {
            if url.path.hasPrefix(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].path + "/") {
                try? FileManager.default.removeItem(at: url)
            }
            message = "音声を読み込めません。もう一度再生してください。\(error.localizedDescription)"
        }
    }
    func pause() { player?.pause(); playing = false; nowPlaying() }
    func seek(_ seconds: Double) {
        if player == nil { play() }
        guard let player = player else { return }
        player.currentTime = min(max(0, seconds), player.duration); position = player.currentTime; nowPlaying()
        updateWord()
    }
    func setTimer(_ minutes: Int) {
        deadline = minutes > 0 ? Date().addingTimeInterval(Double(minutes * 60)) : nil
        remaining = minutes * 60
    }
    private func update() {
        if let deadline = deadline {
            let nextRemaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            if remaining != nextRemaining { remaining = nextRemaining }
            if deadline <= Date() {
                if generating { generationTimedOut = true }
                pause(); self.deadline = nil; message = "スリープタイマーで停止しました"
            }
        }
        let nextPosition = player?.currentTime ?? 0
        if position != nextPosition { position = nextPosition }
        updateWord()
    }
    private func updateWord() {
        let words = currentWords
        var low = 0
        var high = words.count
        while low < high {
            let middle = (low + high) / 2
            if words[middle].start <= position { low = middle + 1 } else { high = middle }
        }
        let candidate = low - 1
        let next: Int? = candidate >= 0 && position < words[candidate].end ? candidate : nil
        if next != activeWord { activeWord = next }
    }
    private func nowPlaying() {
        guard let track = track else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "写真\(track.id) · \(chapter < 0 ? "全章" : "第\(chapter + 1)章") · \(track.title)",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? speed : 0
        ]
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playing = false
        guard flag, repeatMode == .all else { nowPlaying(); return }
        if let deadline = deadline, deadline <= Date() { update(); return }
        guard let track = track, !tracks.isEmpty else { return }
        if chapter >= 0 && chapter + 1 < track.sections.count { chapter += 1 }
        else { selected = (selected + 1) % tracks.count; chapter = chapter < 0 ? -1 : 0 }
        self.player = nil; position = 0; duration = 0
        activeWord = nil
        play()
    }
}

struct ListeningView: View {
    @StateObject private var audio = ListeningAudioModel.shared
    var onHome: () -> Void
    @State private var timerMinutes = 30
    private func clock(_ value: Double) -> String { let n = max(0, Int(value)); return String(format: "%d:%02d", n / 60, n % 60) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("ENGLISH LISTENING").font(.caption.weight(.bold)).tracking(3).foregroundStyle(.secondary)
                    Text("写真の英文を、\n何度でも。").font(.largeTitle.bold())
                    Picker("写真を選択", selection: Binding(get: { audio.selected }, set: { audio.choose($0) })) {
                        ForEach(Array(audio.tracks.enumerated()), id: \.element.id) { index, track in
                            Text("写真\(track.id) · \(track.title)").tag(index)
                        }
                    }.pickerStyle(.menu).disabled(audio.generating).accessibilityIdentifier("listening-photo-picker")
                    if let track = audio.track {
                        Picker("章を選択", selection: Binding(get: { audio.chapter }, set: { audio.chooseChapter($0) })) {
                            Text("写真全体（1〜\(track.sections.count)章）").tag(-1)
                            ForEach(track.sections.indices, id: \.self) { Text("第\($0 + 1)章").tag($0) }
                        }.pickerStyle(.menu).disabled(audio.generating).accessibilityIdentifier("listening-chapter-picker")
                    }
                    VStack(spacing: 15) {
                        Text(audio.message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        if audio.generating { ProgressView() }
                        Slider(value: Binding(get: { audio.position }, set: { audio.seek($0) }), in: 0...max(1, audio.duration)).disabled(audio.duration == 0)
                        HStack { Text(clock(audio.position)); Spacer(); Text(clock(audio.duration)) }.font(.caption.monospacedDigit())
                        HStack(spacing: 35) {
                            Button { audio.seek(audio.position - 15) } label: { Image(systemName: "gobackward.15").font(.title) }
                            Button { audio.playing ? audio.pause() : audio.play() } label: { Image(systemName: audio.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 66)) }.disabled(audio.generating).accessibilityLabel(audio.playing ? "一時停止" : "再生")
                            Button { audio.seek(audio.position + 15) } label: { Image(systemName: "goforward.15").font(.title) }
                        }.accessibilityElement(children: .contain)
                        Picker("ループ", selection: $audio.repeatMode) {
                            ForEach(RepeatMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented)
                        Text(audio.repeatMode == .all ? "全体：写真1→2→3→1の順に繰り返します。章を選んだ場合は次の章へ進みます。" : "選択範囲：選んだ章、または写真全体を繰り返します。オフ：選択範囲の最後で停止します。")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Text("再生速度"); Spacer()
                            Picker("再生速度", selection: $audio.speed) {
                                ForEach([Float(0.7), 0.85, 1, 1.15, 1.3], id: \.self) { Text(String(format: "%.2g×", $0)).tag($0) }
                            }
                        }
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 12) {
                        Label("スリープタイマー", systemImage: "moon.zzz.fill").font(.headline)
                        Stepper("\(timerMinutes)分後に停止", value: $timerMinutes, in: 1...180)
                        HStack {
                            Button("タイマー開始") { audio.setTimer(timerMinutes) }.buttonStyle(.borderedProminent)
                            if audio.deadline != nil { Button("解除") { audio.setTimer(0) } }
                        }
                        if audio.deadline != nil { Text("残り \(clock(Double(audio.remaining)))").monospacedDigit() }
                    }.padding().background(Color.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("英文 · 読んでいる単語をハイライト").font(.headline)
                        Text("単語をタップすると、その位置から聴けます。").font(.caption).foregroundStyle(.secondary)
                        ListeningHighlightedText(text: audio.readingText, words: audio.currentWords,
                            active: audio.activeWord, identity: "\(audio.selected)-\(audio.chapter)",
                            seek: { audio.seek($0) })
                            .frame(height: 400)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    Text("教科書の教材音声を収録。初回からオフライン・画面ロック中も再生できます。").font(.footnote).foregroundStyle(.secondary)
                }.padding(22)
            }.navigationTitle("写真リスニング").navigationBarTitleDisplayMode(.inline).tint(.indigo)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(action: onHome) { Label("ホーム", systemImage: "chevron.left") }.accessibilityLabel("ホームへ戻る") } }
        }
    }
}




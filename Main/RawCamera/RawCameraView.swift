import SwiftUI
import AVFoundation

let rawAccent = Color(red: 0.71, green: 0.64, blue: 0.49)
let rawBackground = Color(red: 0.065, green: 0.065, blue: 0.075)

struct RawCameraView: View {
    let onHome: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = RawCapture()
    @StateObject private var library = RawPhotoLibrary()
    @State private var gallery = false
    @State private var preferences = false
    @State private var exposurePanel = false
    @State private var countdown = 0
    @State private var previousIdleState: Bool?
    @State private var timerTask: Task<Void, Never>?
    @AppStorage("raw-grid") private var grid = false
    @AppStorage("raw-capture-aspect") private var aspect = "Original"
    @AppStorage("raw-timer") private var timer = 0
    @AppStorage("raw-mirror-front") private var mirrorFront = true
    private var currentLens: AVCaptureDevice? { camera.lenses.first { $0.uniqueID == camera.selectedLens } }
    private var visibleLenses: [AVCaptureDevice] { camera.lenses.filter { $0.position == (currentLens?.position ?? .back) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onHome) { Image(systemName: "chevron.left").frame(width: 42, height: 44) }.accessibilityLabel("ホームへ戻る")
                Menu {
                    ForEach(["Original", "1:1", "4:3", "3:4", "9:16", "16:9"], id: \.self) { value in Button(value == "Original" ? "元の比率" : value) { aspect = value } }
                } label: { Image(systemName: "viewfinder").frame(width: 30, height: 44) }.accessibilityLabel("撮影の比率")
                Spacer()
                Menu {
                    if camera.bayerAvailable {
                        Button("12MP · RAW") { choose("RAW", 12) }
                        Button("最大48MP · RAW") { choose("RAW", 48) }.disabled(!camera.supports48)
                    }
                    if camera.proRAWAvailable {
                        Button("12MP · ProRAW") { choose("ProRAW", 12) }
                        Button("48MP · ProRAW") { choose("ProRAW", 48) }.disabled(!camera.supports48)
                    }
                    Button("12MP · HEIC") { choose("HEIC", 12) }
                    Button("48MP · HEIC") { choose("HEIC", 48) }.disabled(!camera.supports48)
                } label: {
                    Text("\(camera.resolutionText) \(camera.mode)").font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5).overlay(Capsule().stroke(.white.opacity(0.35), lineWidth: 0.6))
                }.disabled(camera.capturing || countdown > 0).accessibilityIdentifier("raw-resolution")
                Spacer()
                Menu {
                    ForEach([0, 3, 10], id: \.self) { value in Button(value == 0 ? "タイマーなし" : "\(value)秒") { timer = value } }
                } label: { Image(systemName: timer == 0 ? "stopwatch" : "timer").frame(width: 38, height: 44) }.accessibilityLabel("セルフタイマー")
                Button { preferences = true } label: { Image(systemName: "gearshape").frame(width: 38, height: 44) }
                    .accessibilityLabel("カメラ設定").accessibilityIdentifier("raw-settings")
            }.padding(.horizontal, 8)
            Spacer(minLength: 8)
            ZStack {
                RawCameraPreview(camera: camera).scaleEffect(x: currentLens?.position == .front && !mirrorFront ? -1 : 1, y: 1)
                if grid && camera.ready {
                    GeometryReader { p in
                        Path { path in
                            for f in [CGFloat(1.0/3), CGFloat(2.0/3)] {
                                path.move(to: CGPoint(x: p.size.width*f, y: 0)); path.addLine(to: CGPoint(x: p.size.width*f, y: p.size.height))
                                path.move(to: CGPoint(x: 0, y: p.size.height*f)); path.addLine(to: CGPoint(x: p.size.width, y: p.size.height*f))
                            }
                        }.stroke(.white.opacity(0.3), lineWidth: 0.5)
                    }.allowsHitTesting(false)
                }
                if camera.focusLocked { VStack { Text("AE/AF LOCK").font(.caption2).padding(5).background(.black.opacity(0.6)); Spacer() }.foregroundStyle(.yellow).padding() }
                if countdown > 0 { Text("\(countdown)").font(.system(size: 76, weight: .light)).shadow(radius: 12) }
                if camera.capturing { ProgressView().padding(20).background(.black.opacity(0.7), in: Circle()) }
                if let message = camera.message {
                    VStack(spacing: 15) {
                        Image(systemName: "camera.aperture").font(.title)
                        Text(message).font(.callout).multilineTextAlignment(.center).accessibilityIdentifier("raw-camera-status")
                        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                            Button("設定を開く") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                    }.padding(25).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12)).padding()
                }
                if exposurePanel {
                    VStack { Spacer(); HStack {
                        Image(systemName: "sun.max")
                        Slider(value: $camera.exposure, in: camera.exposureRange).tint(.white)
                            .onChange(of: camera.exposure) { _, value in camera.setExposure(value) }.accessibilityLabel("露出補正")
                        Text(String(format: "%+.1f", camera.exposure)).monospacedDigit().frame(width: 36)
                    }.font(.caption).padding().background(.black.opacity(0.65)) }
                }
            }.aspectRatio(previewRatio, contentMode: .fit).background(.black).clipped()
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                ForEach(visibleLenses, id: \.uniqueID) { lens in
                    Button {
                        camera.select(lens)
                    } label: {
                        Text(lens.deviceType == .builtInUltraWideCamera ? "0.5×" : lens.deviceType == .builtInTelephotoCamera ? "望遠" : "1×")
                            .font(.system(size: 11, weight: .medium)).frame(width: 42, height: 42)
                            .background(camera.selectedLens == lens.uniqueID && camera.zoom == 1 ? Color.white : Color.clear, in: Circle())
                            .foregroundStyle(camera.selectedLens == lens.uniqueID && camera.zoom == 1 ? .black : .white)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                    }
                }
                if currentLens?.deviceType == .builtInWideAngleCamera {
                    Button { camera.setZoom(camera.zoom == 2 ? 1 : 2) } label: {
                        Text("2×").font(.system(size: 11, weight: .medium)).frame(width: 42, height: 42)
                            .background(camera.zoom == 2 ? Color.white : Color.clear, in: Circle())
                            .foregroundStyle(camera.zoom == 2 ? .black : .white).overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 0.5))
                    }.accessibilityLabel("2倍ズーム")
                }
                Button { exposurePanel.toggle() } label: { Image(systemName: "plusminus").frame(width: 34, height: 42) }.accessibilityLabel("露出補正を表示")
            }.disabled(camera.capturing || countdown > 0)
            HStack {
                Button { gallery = true } label: {
                    Group {
                        if let shot = library.shots.first, let image = UIImage(contentsOfFile: library.thumbnail(shot).path) { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image(systemName: "square.grid.3x3") }
                    }.frame(width: 48, height: 48).clipped().clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.7), lineWidth: 0.8))
                }.accessibilityLabel("RAWギャラリー").accessibilityIdentifier("raw-gallery")
                Spacer()
                Button(action: shutter) {
                    Circle().fill(camera.ready ? .white : .gray).frame(width: 56, height: 56).padding(6).overlay(Circle().stroke(.white, lineWidth: 2))
                        .overlay { if countdown > 0 { Image(systemName: "xmark").foregroundStyle(.black) } }
                }.disabled(!camera.ready || camera.capturing).accessibilityLabel("RAWを撮影").accessibilityIdentifier("raw-shutter")
                Spacer()
                Button { camera.switchCamera() } label: { Image(systemName: "arrow.triangle.2.circlepath.camera").frame(width: 48, height: 48) }
                    .accessibilityLabel("カメラを切り替え").disabled(camera.capturing || countdown > 0)
            }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 16)
        }.background(rawBackground).foregroundStyle(.white)
        .onAppear { start() }.onDisappear { stop() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { start() } else { stop() } }
        .onChange(of: gallery) { _, showing in if showing { stop() } }
        .onChange(of: preferences) { _, showing in if showing { stop() } }
        .sheet(isPresented: $gallery, onDismiss: start) { RawGalleryView(library: library, camera: camera) }
        .sheet(isPresented: $preferences, onDismiss: start) { RawPreferencesView(camera: camera) }
        .alert("カメラ", isPresented: Binding(get: { !gallery && (library.error != nil || library.notice != nil || camera.lastCaptureWarning != nil) }, set: { if !$0 { clearNotice() } })) {
            Button("OK") { clearNotice() }
        } message: { Text(library.error ?? camera.lastCaptureWarning ?? library.notice ?? "") }
    }
    private var previewRatio: CGFloat { ["1:1": 1, "4:3": 4.0/3, "3:4": 0.75, "9:16": 9.0/16, "16:9": 16.0/9][aspect] ?? 0.75 }
    private func choose(_ mode: String, _ mp: Int) { camera.setMode(mode); camera.setMegapixels(mp) }
    private func clearNotice() { library.error = nil; library.notice = nil; camera.lastCaptureWarning = nil }
    private func start() {
        guard scenePhase == .active, !gallery, !preferences else { return }
        if previousIdleState == nil { previousIdleState = UIApplication.shared.isIdleTimerDisabled }
        UIApplication.shared.isIdleTimerDisabled = true
        camera.start { data, format, metadata, done in library.add(data: data, format: format, metadata: metadata, completion: done) }
    }
    private func stop() {
        timerTask?.cancel(); timerTask = nil; countdown = 0; camera.stop()
        if let previous = previousIdleState { UIApplication.shared.isIdleTimerDisabled = previous; previousIdleState = nil }
    }
    private func shutter() {
        if countdown > 0 { timerTask?.cancel(); countdown = 0; return }
        guard timer > 0 else { camera.capture(); return }
        let seconds = timer
        timerTask = Task { @MainActor in
            for value in stride(from: seconds, through: 1, by: -1) {
                countdown = value
                do { try await Task.sleep(for: .seconds(1)) } catch { countdown = 0; return }
            }
            countdown = 0; camera.capture()
        }
    }
}

struct RawPreferencesView: View {
    @ObservedObject var camera: RawCapture
    @Environment(\.dismiss) private var dismiss
    @AppStorage("raw-grid") private var grid = false
    @AppStorage("raw-auto-export") private var auto = false
    @AppStorage("raw-export-format") private var format = "JPEG"
    @AppStorage("raw-export-size") private var size = 0
    @AppStorage("raw-default-lens") private var lens = ""
    @AppStorage("raw-mirror-front") private var mirror = true
    @AppStorage("raw-export-location") private var includeLocation = false
    @AppStorage("raw-gallery-columns") private var columns = 5
    var body: some View {
        NavigationStack {
            Form {
                Section("撮影") {
                    Toggle("グリッド", isOn: $grid)
                    Toggle("前面カメラを鏡表示", isOn: $mirror)
                    Toggle("フラッシュ", isOn: $camera.flash)
                    Picker("初期レンズ", selection: $lens) {
                        Text("広角").tag("")
                        ForEach(camera.lenses, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    if !camera.proRAWAvailable && camera.supports48 {
                        Text("このカメラの48MP撮影はHEICを使用します。Bayer RAWとは異なる形式です。").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("書き出し") {
                    Toggle("撮影後に写真へ保存", isOn: $auto)
                    Picker("形式", selection: $format) { Text("JPEG").tag("JPEG"); Text("HEIC").tag("HEIC") }
                    RawExportSizePicker(size: $size)
                    Toggle("元写真の位置情報を含める", isOn: $includeLocation)
                }
                Section("ギャラリー") {
                    Picker("列数", selection: $columns) { ForEach([3, 4, 5], id: \.self) { Text("\($0)列").tag($0) } }
                    Button("標準の現像設定に戻す") { RawPreferences.recipe = RawAdjustments() }
                }
            }.navigationTitle("設定").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } } }
        }.preferredColorScheme(.dark)
    }
}
struct RawExportSizePicker: View {
    @Binding var size: Int
    var body: some View {
        Picker("書き出しサイズ", selection: $size) {
            Text("元のサイズ").tag(0)
            ForEach([4096, 2048, 1280, 1080], id: \.self) { Text("長辺 \($0) px").tag($0) }
        }
    }
}
struct RawShareItem: Identifiable { let id = UUID(); let url: URL }
struct RawShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

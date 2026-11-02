import SwiftUI
import AVFoundation

struct RawCameraView: View {
    let onHome: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = RawCapture()
    @StateObject private var library = RawPhotoLibrary()
    @State private var gallery = false
    @State private var preferences = false
    @AppStorage("raw-grid") private var grid = true
    @AppStorage("raw-auto-export") private var autoExport = false
    private let amber = Color(red: 0.95, green: 0.71, blue: 0.34)
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onHome) { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("ホームへ戻る")
                Spacer()
                Text("RAW CAMERA").font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(3)
                Spacer()
                Button { preferences = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }
                    .accessibilityLabel("カメラ設定").accessibilityIdentifier("raw-settings")
            }.padding(.horizontal, 12).padding(.bottom, 10)
            ZStack {
                RawCameraPreview(camera: camera)
                if grid && camera.ready {
                    GeometryReader { proxy in
                        Path { path in
                            for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                                let x = proxy.size.width * fraction; let y = proxy.size.height * fraction
                                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                                path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                            }
                        }.stroke(.white.opacity(0.3), lineWidth: 0.5)
                    }.allowsHitTesting(false)
                }
                if let message = camera.message {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.aperture").font(.largeTitle).foregroundStyle(amber)
                        Text(message).font(.callout).multilineTextAlignment(.center).accessibilityIdentifier("raw-camera-status")
                        if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                            Button("設定を開く") { UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!) }
                        }
                    }.padding(28).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 16)).padding(20)
                }
                if camera.capturing { ProgressView().tint(amber).padding(20).background(.black.opacity(0.75), in: Circle()) }
            }.aspectRatio(3.0 / 4, contentMode: .fit).background(Color(white: 0.055)).clipped()
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                ForEach(camera.lenses, id: \.uniqueID) { lens in
                    Button { camera.select(lens) } label: {
                        Text(lens.deviceType == .builtInUltraWideCamera ? "0.5×" : lens.deviceType == .builtInTelephotoCamera ? "望遠" : "1×")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .padding(10).background(camera.selectedLens == lens.uniqueID ? amber.opacity(0.23) : Color.white.opacity(0.06), in: Capsule())
                    }.disabled(camera.capturing)
                }
                if camera.proRAWAvailable {
                    Button(camera.useProRAW ? "ProRAW" : "RAW") { camera.useProRAW.toggle() }
                        .font(.system(size: 12, weight: .bold, design: .monospaced)).disabled(camera.capturing || !camera.bayerAvailable)
                }
            }.foregroundStyle(amber)
            HStack(spacing: 12) {
                Image(systemName: "sun.max")
                Slider(value: $camera.exposure, in: camera.exposureRange).tint(amber)
                    .onChange(of: camera.exposure) { camera.setExposure($0) }
                    .accessibilityLabel("露出補正")
                Text(String(format: "%+.1f", camera.exposure)).monospacedDigit().frame(width: 42)
            }.font(.caption).padding(.horizontal, 36).padding(.top, 14).disabled(!camera.ready || camera.capturing)
            HStack {
                Button { gallery = true } label: {
                    Group {
                        if let shot = library.shots.first, let image = UIImage(contentsOfFile: library.thumbnail(shot).path) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else { Image(systemName: "square.grid.2x2").font(.title2) }
                    }.frame(width: 52, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                }.accessibilityLabel("RAWギャラリー").accessibilityIdentifier("raw-gallery")
                Spacer()
                Button { camera.capture() } label: {
                    Circle().fill(camera.ready ? Color.white : Color.gray).frame(width: 64, height: 64)
                        .padding(6).overlay(Circle().stroke(amber, lineWidth: 2))
                }.disabled(!camera.ready || camera.capturing).accessibilityLabel("RAWを撮影").accessibilityIdentifier("raw-shutter")
                Spacer()
                Text(camera.useProRAW ? "DNG\nProRAW" : "DNG\nRAW")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).lineSpacing(4).foregroundStyle(amber).frame(width: 52)
            }.padding(.horizontal, 34).padding(.vertical, 20)
        }
        .background(.black).foregroundStyle(.white)
        .onAppear { startCamera() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !gallery && !preferences { startCamera() } else { camera.stop() }
        }
        .sheet(isPresented: $gallery, onDismiss: { startCamera() }) {
            RawGalleryView(library: library)
        }
        .sheet(isPresented: $preferences, onDismiss: { startCamera() }) {
            NavigationStack {
                Form {
                    Toggle("グリッド", isOn: $grid)
                    Toggle("撮影後にJPEGを写真へ保存", isOn: $autoExport)
                    Section {
                        Text("DNG原本はmain内に保存されます。撮影後、ギャラリーで色と質感を調整できます。RAWとProRAWの対応は機種・レンズによって異なります。")
                    }
                }.navigationTitle("カメラ設定").toolbar { ToolbarItem(placement: .confirmationAction) { Button("完了") { preferences = false } } }
            }.preferredColorScheme(.dark)
        }
        .onChange(of: gallery) { if $0 { camera.stop() } }
        .onChange(of: preferences) { if $0 { camera.stop() } }
        .alert("RAWカメラ", isPresented: Binding(get: { !gallery && (library.error != nil || library.notice != nil) }, set: { if !$0 { library.error = nil; library.notice = nil } })) {
            Button("OK") { library.error = nil; library.notice = nil }
        } message: { Text(library.error ?? library.notice ?? "") }
    }
    private func startCamera() {
        guard scenePhase == .active, !gallery, !preferences else { return }
        camera.start { data, format, done in library.add(data: data, format: format, completion: done) }
    }
}

struct RawGalleryView: View {
    @ObservedObject var library: RawPhotoLibrary
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if library.shots.isEmpty {
                    ContentUnavailableView("まだ写真がありません", systemImage: "camera.aperture")
                } else {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 3), spacing: 3) {
                            ForEach(library.shots) { shot in
                                NavigationLink {
                                    RawEditorView(library: library, shot: shot)
                                } label: { RawThumbnail(url: library.thumbnail(shot), date: shot.date).id(shot) }
                            }
                        }
                    }
                }
            }.navigationTitle("RAWギャラリー").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
                .overlay { if library.busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
                .alert("RAWカメラ", isPresented: Binding(get: { library.error != nil || library.notice != nil }, set: { if !$0 { library.error = nil; library.notice = nil } })) {
                    Button("OK") { library.error = nil; library.notice = nil }
                } message: { Text(library.error ?? library.notice ?? "") }
        }.preferredColorScheme(.dark)
    }
}

private struct RawThumbnail: View {
    let url: URL
    let date: Date
    @State private var image: UIImage?
    var body: some View {
        Color(white: 0.1).aspectRatio(1, contentMode: .fit)
            .overlay { if let image { GeometryReader { p in Image(uiImage: image).resizable().scaledToFill().frame(width: p.size.width, height: p.size.height).clipped() } }
                else { Image(systemName: "doc.richtext").foregroundStyle(.secondary) } }
            .clipped().accessibilityLabel(date.formatted())
            .task { image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value }
    }
}

struct RawEditorView: View {
    @ObservedObject var library: RawPhotoLibrary
    let shot: RawShot
    @Environment(\.dismiss) private var dismiss
    @State private var adjustments = RawAdjustments()
    @State private var image: UIImage?
    @State private var previewError: String?
    @State private var rendering = false
    @State private var share: RawShareItem?
    @State private var confirmDelete = false
    @State private var deleting = false
    private var current: RawShot { var value = shot; value.adjustments = adjustments; return value }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                if rendering { ProgressView() }
                if let previewError { Text(previewError).font(.callout).padding().multilineTextAlignment(.center) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                VStack(spacing: 18) {
                    Picker("現像", selection: $adjustments.look) {
                        Text("Cinema").tag("Cinema"); Text("Neutral").tag("Neutral"); Text("Mono").tag("Mono")
                    }.pickerStyle(.segmented)
                    adjust("露出", value: $adjustments.exposure, range: -3...3)
                    adjust("色温度", value: $adjustments.warmth, range: -1...1)
                    adjust("彩度", value: $adjustments.saturation, range: 0...1.6)
                    adjust("コントラスト", value: $adjustments.contrast, range: 0.7...1.3)
                    adjust("粒子", value: $adjustments.grain, range: 0...1)
                }.padding(20)
            }.frame(maxHeight: 300).background(Color(white: 0.065))
        }
        .navigationTitle(shot.format).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("編集を保存", systemImage: "checkmark") { library.save(shot, adjustments: adjustments) }
                    Button("調整をリセット", systemImage: "arrow.counterclockwise") { adjustments = RawAdjustments() }
                    Section("書き出す") {
                        ForEach(["JPEG", "HEIC", "DNG"], id: \.self) { kind in
                            Button(kind) { library.export(current, kind: kind) { if let url = $0 { share = RawShareItem(url: url) } } }
                        }
                        Button("写真にJPEGを保存") { library.saveToPhotos(current, raw: false) }
                        Button("写真にDNGを保存") { library.saveToPhotos(current, raw: true) }
                    }
                    Button("写真を削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }.disabled(library.busy)
            }
        }
        .onAppear { adjustments = shot.adjustments }
        .task(id: adjustments) {
            let snapshot = adjustments
            do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
            rendering = true
            let result: Result<UIImage, Error> = await withCheckedContinuation { continuation in
                library.queue.async {
                    continuation.resume(returning: Result {
                        let ci = try RawDeveloper.image(library.original(shot), adjustments: snapshot, maxSide: 1600)
                        guard let cg = RawDeveloper.context.createCGImage(ci, from: ci.extent) else { throw RawCameraError.message("プレビューを作成できません。") }
                        return UIImage(cgImage: cg)
                    })
                }
            }
            guard !Task.isCancelled else { return }
            rendering = false
            switch result { case .success(let value): image = value; previewError = nil
            case .failure(let error): previewError = error.localizedDescription }
        }
        .onDisappear { if !deleting && adjustments != shot.adjustments { library.save(shot, adjustments: adjustments) } }
        .sheet(item: $share) { item in RawShareSheet(url: item.url).onDisappear { try? FileManager.default.removeItem(at: item.url) } }
        .confirmationDialog("DNG原本と編集を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("削除", role: .destructive) { deleting = true; library.delete(shot); dismiss() }
        }
    }
    private func adjust(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.caption).frame(width: 80, alignment: .leading)
            Slider(value: value, in: range).tint(Color(red: 0.95, green: 0.71, blue: 0.34)).accessibilityLabel(title)
            Text(String(format: "%.2f", value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 40)
        }
    }
}

private struct RawShareItem: Identifiable { let id = UUID(); let url: URL }
private struct RawShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

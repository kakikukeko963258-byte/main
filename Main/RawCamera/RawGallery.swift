import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct RawGalleryView: View {
    @ObservedObject var library: RawPhotoLibrary
    @ObservedObject var camera: RawCapture
    @Environment(\.dismiss) private var dismiss
    @AppStorage("raw-gallery-columns") private var columns = 5
    @State private var selecting = false, confirmDelete = false, fileImport = false, preferences = false
    @State private var selected: Set<UUID> = []
    @State private var photo: PhotosPickerItem?
    @State private var share: RawShareItem?
    private var chosen: [RawShot] { library.shots.filter { selected.contains($0.id) } }
    private var groups: [(Date, [RawShot])] {
        let grouped = Dictionary(grouping: library.shots) { Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: $0.date)) ?? $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }
    var body: some View {
        NavigationStack {
            Group {
                if library.shots.isEmpty { ContentUnavailableView("まだ写真がありません", systemImage: "camera.aperture") }
                else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(groups, id: \.0) { date, shots in
                                Text(date.formatted(.dateTime.year().month(.wide))).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 12)
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
                                    ForEach(shots) { shot in
                                        if selecting {
                                            Button { if !selected.insert(shot.id).inserted { selected.remove(shot.id) } } label: {
                                                RawThumbnail(url: library.thumbnail(shot), date: shot.date)
                                                    .overlay(alignment: .bottomTrailing) { Image(systemName: selected.contains(shot.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(.white).shadow(radius: 2).padding(4) }
                                            }
                                        } else {
                                            NavigationLink { RawViewerView(library: library, initial: shot, onCamera: { dismiss() }) }
                                            label: { RawThumbnail(url: library.thumbnail(shot), date: shot.date).id("\(shot.id)-\(library.thumbnailRevision)") }.accessibilityIdentifier("raw-shot-\(shot.id)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }.background(rawBackground).navigationTitle(selecting ? "\(selected.count)枚を選択" : "ギャラリー").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(selecting ? "完了" : "選択") { selecting.toggle(); selected.removeAll() }
                        Menu {
                            PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) { Label("写真から読み込む", systemImage: "photo.on.rectangle") }
                            Button("ファイル・アーカイブを読み込む", systemImage: "folder") { fileImport = true }
                            if selecting { Button("すべてを選択") { selected = Set(library.shots.map(\.id)) } }
                            Button("アーカイブを書き出す", systemImage: "archivebox") {
                                library.exportArchive(selecting ? chosen : library.shots) { if let url = $0 { share = RawShareItem(url: url) } }
                            }.disabled(selecting ? chosen.isEmpty : library.shots.isEmpty)
                            Button("設定", systemImage: "gearshape") { preferences = true }
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    if selecting {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button { library.exportArchive(chosen) { if let url = $0 { share = RawShareItem(url: url) } } } label: { Image(systemName: "square.and.arrow.up") }.disabled(chosen.isEmpty || library.busy)
                            Spacer()
                            Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.disabled(chosen.isEmpty || library.busy)
                        }
                    }
                }
                .overlay { if library.busy { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
                .sheet(isPresented: $preferences) { RawPreferencesView(camera: camera) }
                .sheet(item: $share, onDismiss: { share = nil }) { item in RawShareSheet(url: item.url).onDisappear { try? FileManager.default.removeItem(at: item.url) } }
                .fileImporter(isPresented: $fileImport, allowedContentTypes: [.image, .rawCameraArchive, .folder]) { result in
                    switch result {
                    case .success(let url): if url.pathExtension == "rawcamera" { library.importArchive(url) } else { library.importImage(url) }
                    case .failure(let error): library.error = error.localizedDescription
                    }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }
                    Task {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw RawCameraError.message("写真を読み込めません。") }
                            try library.importImageData(data)
                        } catch { library.error = error.localizedDescription }
                        photo = nil
                    }
                }
                .confirmationDialog("選択した\(chosen.count)枚の原本と編集を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("削除", role: .destructive) { for shot in chosen { library.delete(shot) }; selected.removeAll(); selecting = false }
                }
                .alert("カメラ", isPresented: Binding(get: { library.error != nil || library.notice != nil }, set: { if !$0 { library.error = nil; library.notice = nil } })) {
                    Button("OK") { library.error = nil; library.notice = nil }
                } message: { Text(library.error ?? library.notice ?? "") }
        }.preferredColorScheme(.dark).tint(.white)
    }
}
struct RawThumbnail: View {
    let url: URL
    let date: Date
    @State private var image: UIImage?
    var body: some View {
        Color(white: 0.1).aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image { GeometryReader { p in Image(uiImage: image).resizable().scaledToFill().frame(width: p.size.width, height: p.size.height).clipped() } }
                else { Image(systemName: "doc.richtext").foregroundStyle(.secondary) }
            }.clipped().accessibilityLabel(date.formatted())
            .task(id: url) { image = await Task.detached(priority: .utility) { UIImage(contentsOfFile: url.path) }.value }
    }
}

private struct RawRenderRequest: Equatable { var id: UUID; var adjustments: RawAdjustments; var compare: Bool }
struct RawViewerView: View {
    @ObservedObject var library: RawPhotoLibrary
    let onCamera: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID
    @State private var adjustments: RawAdjustments
    @State private var undo: [RawAdjustments] = [], redo: [RawAdjustments] = []
    @State private var beforeGesture: RawAdjustments?
    @State private var image: UIImage?
    @State private var error: String?
    @State private var editing = false, comparing = false, rendering = false, deleting = false
    @State private var category = "Tone", texture = "Grain"
    @State private var share: RawShareItem?
    @State private var pendingExport: String?
    @State private var confirmDelete = false, exportSheet = false, info = false
    @AppStorage("raw-export-format") private var exportFormat = "JPEG"
    @AppStorage("raw-export-size") private var exportSize = 0
    private var shot: RawShot? { library.shots.first { $0.id == selectedID } }
    private var request: RawRenderRequest { RawRenderRequest(id: selectedID, adjustments: adjustments, compare: comparing) }
    init(library: RawPhotoLibrary, initial: RawShot, onCamera: @escaping () -> Void) {
        self.library = library; self.onCamera = onCamera
        _selectedID = State(initialValue: initial.id); _adjustments = State(initialValue: initial.adjustments)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "square.grid.3x3").frame(width: 38, height: 38) }.accessibilityLabel("ギャラリー")
                Button { exportSheet = true } label: { Image(systemName: "square.and.arrow.up").frame(width: 38, height: 38) }.accessibilityLabel("書き出す")
                if editing {
                    Button(action: undoEdit) { Image(systemName: "arrow.uturn.backward").frame(width: 32, height: 38) }.disabled(undo.isEmpty).accessibilityIdentifier("raw-undo")
                    Button(action: redoEdit) { Image(systemName: "arrow.uturn.forward").frame(width: 32, height: 38) }.disabled(redo.isEmpty).accessibilityIdentifier("raw-redo")
                }
                Spacer()
                Menu {
                    Button("写真の情報", systemImage: "info.circle") { info = true }
                    Button("この現像設定を標準にする") { RawPreferences.recipe = adjustments }
                    Button("すべての調整をリセット") { change { adjustments = RawAdjustments() } }
                    Button("原本を書き出す") { export("Original") }
                    Button("写真を削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle").frame(width: 38, height: 38) }
            }.font(.system(size: 15)).padding(.horizontal, 8).disabled(library.busy)
            HStack(alignment: .top) {
                Button { info = true } label: { Image(systemName: "info.circle").frame(width: 30, height: 24) }
                Spacer()
                if let shot {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(shot.date.formatted(date: .abbreviated, time: .shortened))
                        if let c = shot.capture { Text(String(format: "%@ · %.1fMP · %d × %d", shot.format, c.megapixels, c.width, c.height)) }
                    }.font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12)
            ZStack {
                Color.clear
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                if rendering { ProgressView().padding(10).background(.black.opacity(0.6), in: Circle()) }
                if let error { Text(error).font(.callout).multilineTextAlignment(.center).padding() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.3, pressing: { comparing = $0 }, perform: {})
                .accessibilityLabel(comparing ? "原本を比較中" : "現像した写真")
            if editing { editorControls }
            if !editing {
                Button { editing = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 40).background(.white.opacity(0.06), in: Circle()) }.accessibilityLabel("編集").accessibilityIdentifier("raw-edit")
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 3) {
                            ForEach(library.shots) { candidate in
                                Button { select(candidate) } label: {
                                    RawThumbnail(url: library.thumbnail(candidate), date: candidate.date)
                                        .frame(width: 42, height: 48).clipped()
                                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(candidate.id == selectedID ? .white : .clear, lineWidth: 2)).padding(2)
                                }.id(candidate.id)
                            }
                        }.padding(.horizontal, 8)
                    }.frame(height: 56).onAppear { proxy.scrollTo(selectedID, anchor: .center) }
                        .onChange(of: selectedID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            } else {
                HStack {
                    tab("Tone", icon: "chart.xyaxis.line", text: "階調")
                    tab("Color", icon: "paintpalette", text: "色")
                    tab("Texture", icon: "sparkles", text: "質感")
                    tab("Crop", icon: "crop", text: "クロップ")
                    Button { persist(); onCamera() } label: { Image(systemName: "camera").frame(maxWidth: .infinity).frame(height: 42) }.accessibilityLabel("撮影に戻る")
                }.padding(.bottom, 8)
            }
        }.background(rawBackground).foregroundStyle(.white).navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
            .task(id: request) { await render() }
            .onDisappear { if !deleting { persist() } }
            .sheet(item: $share) { item in RawShareSheet(url: item.url).onDisappear { try? FileManager.default.removeItem(at: item.url) } }
            .sheet(isPresented: $exportSheet, onDismiss: { if let kind = pendingExport { pendingExport = nil; export(kind) } }) { exportControls }
            .sheet(isPresented: $info) { metadataView }
            .confirmationDialog("原本と編集を削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("削除", role: .destructive) { deleting = true; if let shot { library.delete(shot) }; dismiss() }
            }
    }
    private var editorControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(category == "Tone" ? "階調" : category == "Color" ? "色" : category == "Texture" ? "質感" : "クロップ").font(.caption).foregroundStyle(.secondary)
                    Spacer(); Button("完了") { persist(); editing = false }.font(.caption)
                }
                switch category {
                case "Tone":
                    adjust("露出", $adjustments.exposure, -4...4)
                    adjust("コントラスト", $adjustments.contrast, 0.5...1.5)
                    adjust("ハイライト", $adjustments.highlights, 0...1)
                    adjust("シャドウ", $adjustments.shadows, -1...1)
                    adjust("黒レベル", $adjustments.blackPoint, -0.1...0.1)
                case "Color":
                    Picker("現像", selection: Binding(get: { adjustments.look }, set: { value in change { adjustments.look = value } })) {
                        Text("Cinema").tag("Cinema"); Text("Neutral").tag("Neutral"); Text("Mono").tag("Mono")
                    }.pickerStyle(.segmented)
                    adjust("色温度", $adjustments.warmth, -1...1)
                    adjust("ティント", $adjustments.tint, -100...100)
                    adjust("彩度", $adjustments.saturation, 0...2)
                case "Texture":
                    Picker("質感", selection: $texture) { Text("Grain").tag("Grain"); Text("Halation").tag("Halation") }.pickerStyle(.segmented)
                    if texture == "Grain" {
                        adjust("Amplitude", $adjustments.grain, 0...2)
                        adjust("Grain Size", $adjustments.grainSize, 0.25...4)
                        Toggle("Force Pixel Size Grain", isOn: Binding(get: { adjustments.forcePixelGrain }, set: { value in change { adjustments.forcePixelGrain = value } })).font(.caption)
                    } else {
                        adjust("Amplitude", $adjustments.halation, 0...2)
                        adjust("Halation Size", $adjustments.halationRadius, 0.25...4)
                    }
                default:
                    Picker("比率", selection: Binding(get: { adjustments.cropAspect }, set: { value in change { adjustments.cropAspect = value } })) {
                        ForEach(["Original", "1:1", "4:3", "3:2", "16:9", "3:4", "9:16"], id: \.self) { Text($0 == "Original" ? "元の比率" : $0).tag($0) }
                    }.font(.caption)
                    HStack(spacing: 22) {
                        Button { change { adjustments.rotation = (adjustments.rotation + 3) % 4 } } label: { Image(systemName: "rotate.left") }.accessibilityLabel("左に回転")
                        Button { change { adjustments.rotation = (adjustments.rotation + 1) % 4 } } label: { Image(systemName: "rotate.right") }.accessibilityLabel("右に回転")
                        Button { change { adjustments.flipH.toggle() } } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }.accessibilityLabel("左右反転")
                        Button { change { adjustments.flipV.toggle() } } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }.accessibilityLabel("上下反転")
                        Button("リセット") { change { adjustments.rotation = 0; adjustments.flipH = false; adjustments.flipV = false; adjustments.cropAspect = "Original"; adjustments.cropZoom = 1; adjustments.cropX = 0.5; adjustments.cropY = 0.5 } }.font(.caption)
                    }
                    adjust("ズーム", $adjustments.cropZoom, 1...4)
                    adjust("横位置", $adjustments.cropX, 0...1)
                    adjust("縦位置", $adjustments.cropY, 0...1)
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }.frame(height: category == "Tone" || category == "Crop" ? 240 : 180)
    }
    private func tab(_ name: String, icon: String, text: String) -> some View {
        Button { category = name } label: { VStack(spacing: 4) { Image(systemName: icon); Text(text).font(.system(size: 9)) }.foregroundStyle(category == name ? .white : .gray).frame(maxWidth: .infinity).frame(height: 42) }.accessibilityIdentifier("raw-tab-\(name)")
    }
    private func adjust(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(String(format: "%.2f", value.wrappedValue)).monospacedDigit() }.font(.system(size: 10)).foregroundStyle(.secondary)
            Slider(value: value, in: range, onEditingChanged: { started in
                if started { beforeGesture = adjustments }
                else if let before = beforeGesture, before != adjustments { undo.append(before); if undo.count > 100 { undo.removeFirst() }; redo.removeAll(); beforeGesture = nil }
            }).tint(.white).accessibilityLabel(title)
        }
    }
    private func change(_ action: () -> Void) { let before = adjustments; action(); if before != adjustments { undo.append(before); redo.removeAll() } }
    private func undoEdit() { guard let value = undo.popLast() else { return }; redo.append(adjustments); adjustments = value }
    private func redoEdit() { guard let value = redo.popLast() else { return }; undo.append(adjustments); adjustments = value }
    private func persist() { if let shot, shot.adjustments != adjustments { library.save(shot, adjustments: adjustments) } }
    private func select(_ next: RawShot) { persist(); selectedID = next.id; adjustments = next.adjustments; undo.removeAll(); redo.removeAll(); image = nil; comparing = false }
    private func export(_ kind: String) {
        if exportSheet { pendingExport = kind; exportSheet = false; return }
        guard var value = shot else { return }; value.adjustments = adjustments
        exportSheet = false
        library.export(value, kind: kind) { url in if let url { share = RawShareItem(url: url) } }
    }
    private var exportControls: some View {
        NavigationStack {
            Form {
                Picker("形式", selection: $exportFormat) { Text("JPEG").tag("JPEG"); Text("HEIC").tag("HEIC") }
                RawExportSizePicker(size: $exportSize)
                Button("書き出して共有") { export(exportFormat) }
                Button("写真に保存") { if var value = shot { value.adjustments = adjustments; library.saveToPhotos(value, raw: false, kind: exportFormat) }; exportSheet = false }
                Button("原本を共有") { export("Original") }
                if shot?.isRAW == true { Button("DNGを写真に保存") { if let shot { library.saveToPhotos(shot, raw: true) }; exportSheet = false } }
            }.navigationTitle("書き出し").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { exportSheet = false } } }
        }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }
    private var metadataView: some View {
        NavigationStack {
            Form {
                if let shot {
                    LabeledContent("撮影日時", value: shot.date.formatted())
                    LabeledContent("原本", value: shot.format)
                    if let c = shot.capture {
                        LabeledContent("解像度", value: "\(c.width) × \(c.height)")
                        LabeledContent("画素数", value: String(format: "%.2f MP", c.megapixels))
                        if let lens = c.lens { LabeledContent("レンズ", value: lens) }
                        if let iso = c.iso { LabeledContent("ISO", value: String(format: "%.0f", iso)) }
                        if let seconds = c.seconds { LabeledContent("シャッター", value: seconds < 1 ? String(format: "1/%.0f 秒", 1/seconds) : String(format: "%.2f 秒", seconds)) }
                        if let aperture = c.aperture { LabeledContent("絞り", value: String(format: "f/%.1f", aperture)) }
                    }
                    if let size = try? library.original(shot).resourceValues(forKeys: [.fileSizeKey]).fileSize { LabeledContent("原本サイズ", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
                }
            }.navigationTitle("写真の情報").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { info = false } } }
        }.presentationDetents([.medium, .large]).preferredColorScheme(.dark)
    }
    private func render() async {
        guard let shot else { return }
        let r = request
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        rendering = true
        var recipe = r.adjustments
        if r.compare { recipe = RawAdjustments(); recipe.look = "Neutral"; recipe.grain = 0; recipe.halation = 0 }
        let finalRecipe = recipe
        let result: Result<UIImage, Error> = await withCheckedContinuation { done in
            library.queue.async {
                done.resume(returning: Result {
                    let ci = try RawDeveloper.image(library.original(shot), adjustments: finalRecipe, maxSide: 1600)
                    guard let cg = RawDeveloper.context.createCGImage(ci, from: ci.extent) else { throw RawCameraError.message("プレビューを作成できません。") }
                    return UIImage(cgImage: cg)
                })
            }
        }
        guard !Task.isCancelled else { return }
        rendering = false
        switch result { case .success(let value): image = value; error = nil; case .failure(let failure): error = failure.localizedDescription }
    }
}

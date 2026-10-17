import SwiftUI
import PhotosUI

@main
struct MainApp: App {
    var body: some Scene {
        WindowGroup { HomeView().preferredColorScheme(.dark) }
    }
}

struct HomeItem: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var slots: [Int]
    var isFolder: Bool { slots.count > 1 }
    var displayName: String { isFolder ? name : slots.first.map(String.init) ?? name }
    static let initial: [HomeItem] = [
        HomeItem(id: "app-1", name: "1", slots: [1]),
        HomeItem(id: "app-2", name: "2", slots: [2]),
        HomeItem(id: "navigation", name: "ナビゲーション", slots: Array(3...7)),
        HomeItem(id: "utilities", name: "ユーティリティ", slots: Array(8...12))
    ] + (13...32).map { HomeItem(id: "app-\($0)", name: "\($0)", slots: [$0]) }
}

final class HomeStore: ObservableObject {
    @Published var items: [HomeItem] { didSet { save() } }
    @Published private(set) var hiddenSlots: [Int] = UserDefaults.standard.array(forKey: "hidden-slots") as? [Int] ?? []
    init() {
        if ProcessInfo.processInfo.arguments.contains("-reset-home") {
            UserDefaults.standard.removeObject(forKey: "home-layout-v2")
            UserDefaults.standard.removeObject(forKey: "hidden-slots")
            hiddenSlots = []
        }
        if let data = UserDefaults.standard.data(forKey: "home-layout-v2"),
           let saved = try? JSONDecoder().decode([HomeItem].self, from: data),
           (saved.flatMap(\.slots) + (UserDefaults.standard.array(forKey: "hidden-slots") as? [Int] ?? [])).sorted() == Array(1...32) {
            items = saved.map { item in
                var repaired = item
                if repaired.slots.count == 1 { repaired.name = String(repaired.slots[0]) }
                return repaired
            }
        } else {
            items = HomeItem.initial
            hiddenSlots = []
            UserDefaults.standard.removeObject(forKey: "hidden-slots")
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "home-layout-v2")
        }
    }
    func removeFromHome(_ id: String) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        hiddenSlots = Array(Set(hiddenSlots + item.slots)).sorted()
        UserDefaults.standard.set(hiddenSlots, forKey: "hidden-slots")
        items.removeAll { $0.id == id }
    }
    func restore(_ slot: Int) {
        guard hiddenSlots.contains(slot) else { return }
        hiddenSlots.removeAll { $0 == slot }
        UserDefaults.standard.set(hiddenSlots, forKey: "hidden-slots")
        items.append(HomeItem(id: UUID().uuidString, name: String(slot), slots: [slot]))
    }
    func merge(source: String, target: String) {
        guard source != target,
              let from = items.first(where: { $0.id == source }),
              let to = items.first(where: { $0.id == target }) else { return }
        var result = items.filter { $0.id != source }
        guard let index = result.firstIndex(where: { $0.id == target }) else { return }
        result[index].slots = to.slots + from.slots
        if !to.isFolder { result[index].name = "フォルダ" }
        items = result
    }
    func rename(_ id: String, to name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isFolder else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        items[index].name = String(clean.prefix(24))
    }
    func extract(_ slot: Int, from id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].slots.count > 1 else { return }
        var result = items
        result[index].slots.removeAll { $0 == slot }
        if result[index].slots.count == 1 { result[index].name = "\(result[index].slots[0])" }
        result.append(HomeItem(id: UUID().uuidString, name: "\(slot)", slots: [slot]))
        items = result
    }
    func applyOrder(_ order: [HomeItem]) {
        guard order.count == items.count, Set(order.map(\.id)) == Set(items.map(\.id)) else { return }
        items = order
    }
    func orderSlots(_ slots: [Int], in id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              slots.sorted() == items[index].slots.sorted() else { return }
        items[index].slots = slots
    }
    func move(source: String, target: String) {
        guard source != target, let sourceIndex = items.firstIndex(where: { $0.id == source }),
              let targetIndex = items.firstIndex(where: { $0.id == target }) else { return }
        var result = items
        let item = result.remove(at: sourceIndex)
        result.insert(item, at: min(targetIndex, result.count))
        items = result
    }
    func moveSlot(_ slot: Int, in folder: String, to target: Int) {
        guard slot != target, let index = items.firstIndex(where: { $0.id == folder }),
              let from = items[index].slots.firstIndex(of: slot),
              let to = items[index].slots.firstIndex(of: target) else { return }
        var result = items
        result[index].slots.remove(at: from)
        result[index].slots.insert(slot, at: min(to, result[index].slots.count))
        items = result
    }
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.24), lineWidth: 0.7))
        }
    }
}
extension View {
    func homeGlass(_ radius: CGFloat) -> some View { modifier(GlassSurface(radius: radius)) }
}

struct Wallpaper: View {
    var image: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image ?? WallpaperArtwork.image(size: geometry.size))
                .resizable().scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea()
    }
}

struct SlotIcon: View {
    let slot: Int
    var body: some View {
        Image(uiImage: IconArtwork.image(slot)).resizable().interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
    }
}

struct FolderIcon: View {
    let item: HomeItem
    var body: some View {
        GeometryReader { geo in
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: geo.size.width * 0.045), count: 3), spacing: geo.size.width * 0.045) {
                ForEach(Array(item.slots.prefix(9)), id: \.self) { slot in
                    SlotIcon(slot: slot)
                }
            }.padding(geo.size.width * 0.14)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .modifier(IconGlass())
        }.aspectRatio(1, contentMode: .fit)
    }
}

struct IconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct HomeView: View {
    @StateObject private var store = HomeStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var folderID: String?
    @State private var folderProgress: CGFloat = 0
    @State private var folderSource = CGRect.zero
    @State private var removalItem: HomeItem?
    @State private var selectedSlot: Int?
    @State private var appProgress: CGFloat = 0
    @State private var appInteracting = false
    @State private var appSource = CGRect.zero
    @State private var screenSize = CGSize(width: 390, height: 844)
    @State private var safeTop: CGFloat = 47
    @State private var safeBottom: CGFloat = 34
    @State private var pagePan: CGFloat = 0
    @State private var edgeDirection = 0
    @State private var page = 0
    @State private var showSearch = false
    @State private var query = ""
    @State private var photo: PhotosPickerItem?
    @State private var wallpaper: UIImage?
    @State private var wallpaperError = false
    @State private var folderName = ""
    @State private var editing = false
    @State private var iconMenu: IconMenuSelection?
    @State private var draggedItem: HomeItem?
    @StateObject private var liftFeedback = LiftFeedback()
    @State private var liftKey: String?
    @State private var dragPreview: [HomeItem]?
    @State private var folderPreview: [Int]?
    @State private var hoverCell: Int?
    @State private var dragOrigin = CGRect.zero
    @State private var dragTranslation = CGSize.zero
    @State private var hoveredID: String?
    @State private var hoverStart = Date.distantPast
    @State private var suppressTapUntil = Date.distantPast
    @State private var folderDraggedSlot: Int?
    private var folderMotion: Animation { reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.88) }
    private var appMotion: Animation { reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.45, dampingFraction: 0.90) }
    private var wallpaperURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wallpaper.jpg") }

    var body: some View {
        GeometryReader { geometry in
            let metrics = HomeMetrics(size: geometry.size, homeOffset: (safeTop - safeBottom) / 2)
            ZStack(alignment: .topLeading) {
                Wallpaper(image: wallpaper)
                    .blur(radius: reduceMotion ? 0 : 6 * folderProgress)
                homePages(metrics)
                    .compositingGroup()
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.07 * folderProgress)
                    .blur(radius: 10 * folderProgress)
                    .opacity(1 - 0.12 * folderProgress)
                    .allowsHitTesting(folderID == nil && selectedSlot == nil)
                    .accessibilityHidden(folderID != nil || selectedSlot != nil)
                if let id = folderID, let item = store.items.first(where: { $0.id == id }) {
                    folderOverlay(item, id: id, metrics: metrics)
                    .opacity(reduceMotion ? folderProgress : 1)
                    .allowsHitTesting(selectedSlot == nil)
                    .accessibilityHidden(selectedSlot != nil)
                    .zIndex(2)
                }
                if let slot = selectedSlot {
                    AppTransitionLayer(progress: reduceMotion ? 1 : appProgress, animated: !reduceMotion, interactive: appInteracting, slot: slot,
                                       source: appSource, size: geometry.size, safeTop: safeTop, wallpaper: wallpaper,
                                       close: closeApp,
                                       dragChanged: { amount in
                                           appInteracting = true
                                           appProgress = 1 - min(0.55, max(0, amount / geometry.size.height))
                                       },
                                       dragEnded: { dismiss in
                        appInteracting = false
                        if dismiss { closeApp() } else { appProgress = 1 }
                    })
                    .opacity(reduceMotion ? appProgress : 1).zIndex(3)
                }
                if let selection = iconMenu {
                    HomeIconMenu(selection: selection, size: geometry.size,
                        open: {
                            finishEditing()
                            suppressTapUntil = .distantPast
                            openItem(selection.item, source: selection.source)
                        },
                        edit: { iconMenu = nil; cancelLift(); editing = true },
                        remove: {
                            finishEditing()
                            if let folder = selection.folderID, let slot = selection.item.slots.first {
                                store.extract(slot, from: folder)
                                if !store.items.contains(where: { $0.id == folder && $0.isFolder }) { closeFolder() }
                            } else { removalItem = selection.item }
                        }, dismiss: finishEditing)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(15)
                }
                if let item = draggedItem {
                    Group {
                        if item.isFolder { FolderIcon(item: item) }
                        else { SlotIcon(slot: item.slots[0]) }
                    }.frame(width: metrics.icon, height: metrics.icon)
                        .scaleEffect(1.04)
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 5)
                        .position(x: dragOrigin.midX + dragTranslation.width,
                                  y: dragOrigin.midY + dragTranslation.height)
                        .transaction { $0.animation = nil }
                        .allowsHitTesting(false).accessibilityHidden(true).zIndex(20)
                }
                if editing && draggedItem == nil {
                    Button("完了", action: finishEditing)
                        .buttonStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 16).padding(.vertical, 9).homeGlass(24)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 1706.5 / 2048).zIndex(25)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .coordinateSpace(name: "home")
                .foregroundStyle(.white)
                .onAppear {
                    screenSize = geometry.size
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first(where: { $0.isKeyWindow }) {
                        safeTop = window.safeAreaInsets.top
                        safeBottom = window.safeAreaInsets.bottom
                    }
                }
                .onChange(of: geometry.size) { screenSize = $0 }
        }
        .ignoresSafeArea()
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                finishEditing()
                folderDraggedSlot = nil
                hoveredID = nil
                edgeDirection = 0
                pagePan = 0
            }
        }
        .sheet(isPresented: $showSearch) { searchSheet }
        .task {
            for slot in 1...32 { _ = IconArtwork.image(slot) }
            if let data = try? Data(contentsOf: wallpaperURL) { wallpaper = WallpaperArtwork.downsample(data) }
        }
        .onChange(of: photo) { value in
            Task {
                guard let value else { return }
                do {
                    guard let data = try await value.loadTransferable(type: Data.self),
                          let image = WallpaperArtwork.downsample(data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
                        wallpaperError = true; return
                    }
                    try jpeg.write(to: wallpaperURL, options: .atomic)
                    withAnimation(.easeInOut(duration: 0.25)) { wallpaper = image }
                } catch { wallpaperError = true }
            }
        }
        .confirmationDialog("ホーム画面から取り除きますか？", isPresented: Binding(
            get: { removalItem != nil }, set: { if !$0 { removalItem = nil } }
        ), titleVisibility: .visible) {
            if let item = removalItem {
                Button("ホーム画面から取り除く", role: .destructive) {
                    store.removeFromHome(item.id)
                    page = min(page, max(0, (store.items.count - 1) / 24))
                    removalItem = nil
                }
            }
            Button("キャンセル", role: .cancel) { removalItem = nil }
        } message: {
            Text("番号ページは検索から開けます。検索の長押しメニューからホーム画面に戻せます。")
        }
        .alert("背景を読み込めませんでした", isPresented: $wallpaperError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func folderOverlay(_ item: HomeItem, id: String, metrics: HomeMetrics) -> FolderTransitionLayer {
        var displayItem = item
        displayItem.slots = folderPreview ?? item.slots
        return FolderTransitionLayer(progress: reduceMotion ? 1 : folderProgress,
            item: displayItem, source: folderSource, metrics: metrics, name: $folderName,
            open: { slot, rect in open(slot, source: rect) }, close: closeFolder,
            editing: editing, blankTap: finishEditing,
            prepareLift: { liftFeedback.prepare() },
            beginLift: { slot in
                guard liftKey == nil else { return }
                liftKey = "folder-\(slot)"
                liftFeedback.fire()
                suppressTapUntil = Date().addingTimeInterval(0.8)
                dragOrigin = metrics.folderIconRect((item.slots.firstIndex(of: slot) ?? 0) % 9)
                dragTranslation = .zero
                if editing { startFolderDrag(slot, item: item) }
                else {
                    let child = HomeItem(id: "folder-\(slot)", name: String(slot), slots: [slot])
                    withAnimation(.easeOut(duration: 0.16)) {
                        iconMenu = IconMenuSelection(item: child, source: dragOrigin, folderID: id)
                    }
                }
            },
            draggingSlot: folderDraggedSlot,
            dragChanged: { slot, translation in
                if folderDraggedSlot == nil && hypot(translation.width, translation.height) > 6 {
                    startFolderDrag(slot, item: item)
                }
                guard folderDraggedSlot != nil else { return }
                dragTranslation = translation
                let point = CGPoint(x: dragOrigin.midX + translation.width, y: dragOrigin.midY + translation.height)
                guard var slots = folderPreview, let from = slots.firstIndex(of: slot),
                      let to = slots.indices.first(where: { $0 / 9 == from / 9 && metrics.folderIconRect($0 % 9).insetBy(dx: -8, dy: -12).contains(point) }),
                      from != to else { return }
                slots.remove(at: from)
                slots.insert(slot, at: to)
                withAnimation(reorderMotion) { folderPreview = slots }
            },
            dragEnded: { slot, translation in
                guard folderDraggedSlot != nil else { cancelLift(); return }
                let point = CGPoint(x: dragOrigin.midX + translation.width, y: dragOrigin.midY + translation.height)
                if !metrics.folderRect.insetBy(dx: -12, dy: -12).contains(point) {
                    store.extract(slot, from: id)
                    if let extracted = store.items.first(where: { $0.slots == [slot] }),
                       let target = store.items.enumerated().first(where: { index, candidate in
                           index / 24 == page && candidate.id != extracted.id && metrics.iconRect(index % 24).contains(point)
                       })?.element {
                        store.move(source: extracted.id, target: target.id)
                    }
                    closeFolder()
                } else if let slots = folderPreview { store.orderSlots(slots, in: id) }
                cancelLift()
                suppressTapUntil = Date().addingTimeInterval(0.25)
            },
            rename: { store.rename(id, to: folderName) },
            extract: { slot in
                withAnimation(folderMotion) { store.extract(slot, from: id) }
                if !store.items.contains(where: { $0.id == id && $0.isFolder }) { closeFolder() }
            })
    }
    private func startFolderDrag(_ slot: Int, item: HomeItem) {
        iconMenu = nil
        editing = true
        folderDraggedSlot = slot
        folderPreview = item.slots
        draggedItem = HomeItem(id: "folder-drag", name: String(slot), slots: [slot])
    }
    private var reorderMotion: Animation { reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.27, dampingFraction: 0.86) }
    private var displayedItems: [HomeItem] { dragPreview ?? store.items }
    private func homePages(_ metrics: HomeMetrics) -> some View {
        ZStack {
            // One stable ForEach keeps the touched view alive while its slot changes,
            // including a move across a page boundary. Only positions animate.
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: CGFloat(max(1, (store.items.count + 23) / 24)) * metrics.size.width,
                           height: metrics.size.height)
                    .contentShape(Rectangle()).onTapGesture(perform: finishEditing)
                ForEach(Array(displayedItems.enumerated()), id: \.element.id) { index, item in
                    let rect = metrics.iconRect(index % 24)
                    homeTile(item, metrics: metrics, rect: rect)
                        .frame(width: metrics.cell, height: metrics.tileHeight)
                        .position(x: rect.midX + CGFloat(index / 24) * metrics.size.width,
                                  y: rect.minY + metrics.tileHeight / 2)
                        .opacity(folderID == item.id || (selectedSlot.map { item.slots == [$0] } ?? false) ? 0 : 1)
                }
            }.frame(width: metrics.size.width, height: metrics.size.height, alignment: .topLeading)
            .offset(x: -CGFloat(page) * metrics.size.width + pagePan)
            .frame(width: metrics.size.width, height: metrics.size.height, alignment: .leading)
            .clipped().contentShape(Rectangle())
            .animation(.spring(response: 0.32, dampingFraction: 0.94), value: page)
            .simultaneousGesture(DragGesture(minimumDistance: 25).onChanged { value in
                guard !editing && draggedItem == nil else { return }
                pagePan = value.translation.width
            }.onEnded { value in
                guard !editing && draggedItem == nil else { return }
                let delta = value.predictedEndTranslation.width
                withAnimation(.spring(response: 0.32, dampingFraction: 0.94)) {
                    if delta < -metrics.size.width * 0.2 { page = min(page + 1, max(0, (store.items.count - 1) / 24)) }
                    if delta > metrics.size.width * 0.2 { page = max(0, page - 1) }
                    pagePan = 0
                }
            })
            Button { finishEditing(); showSearch = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: metrics.label, weight: .semibold))
                    Text("検索").font(.system(size: metrics.label, weight: .medium))
                }
                .frame(width: metrics.size.width * 146 / 947, height: metrics.size.height * 73 / 2048)
                .homeGlass(40)
            }.buttonStyle(IconPressStyle())
                .position(x: metrics.size.width / 2, y: metrics.size.height * 1706.5 / 2048)
        }
    }
    private func homeTile(_ item: HomeItem, metrics: HomeMetrics, rect: CGRect) -> some View {
        Button {
            guard !editing && Date() > suppressTapUntil else { return }
            openItem(item, source: rect)
        } label: {
            VStack(spacing: metrics.labelGap) {
                Group {
                    if item.isFolder { FolderIcon(item: item) }
                    else { SlotIcon(slot: item.slots[0]) }
                }.frame(width: metrics.icon, height: metrics.icon)
                    .overlay(IconContour().stroke(.white.opacity(hoveredID == item.id ? 0.8 : 0), lineWidth: 2))
                Text(item.displayName).font(.system(size: metrics.label)).lineLimit(1)
                    .frame(width: metrics.cell, height: metrics.labelHeight)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }.frame(width: metrics.cell, height: metrics.tileHeight).contentShape(Rectangle())
                .opacity(draggedItem?.id == item.id ? 0 : 1)
                .modifier(EditingWiggle(active: editing && draggedItem?.id != item.id,
                                        seed: item.slots.first ?? 0,
                                        anchor: UnitPoint(x: 0.5, y: metrics.icon / (2 * metrics.tileHeight))))
        }.buttonStyle(IconPressStyle())
            .accessibilityLabel(item.isFolder ? "\(item.name)、\(item.slots.count)個のアプリ" : "アプリ \(item.displayName)")
            .overlay {
                IconTouchSurface(
                    exclusion: editing ? CGRect(x: (metrics.cell - metrics.icon) / 2 - 7, y: -7, width: 24, height: 24) : nil,
                    prepare: { liftFeedback.prepare() },
                    tap: {
                        guard !editing && Date() > suppressTapUntil else { return }
                        openItem(item, source: rect)
                    },
                    began: { beginHomeLift(item, rect: rect) },
                    changed: { translation in
                        if draggedItem == nil && hypot(translation.width, translation.height) > 6 { startHomeDrag(item) }
                        if draggedItem != nil { updateHomeLift(translation, metrics: metrics) }
                    },
                    ended: { translation in
                        if draggedItem != nil {
                            updateHomeLift(translation, metrics: metrics)
                            finishMove(item)
                        } else { cancelLift() }
                    }, cancelled: cancelLift)
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { removalItem = item } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black).frame(width: 24, height: 24)
                            .background(.white.opacity(0.9), in: Circle())
                    }.buttonStyle(.plain)
                        .opacity(draggedItem?.id == item.id ? 0 : 1)
                        .offset(x: (metrics.cell - metrics.icon) / 2 - 7, y: -7)
                        .accessibilityLabel("\(item.displayName)をホーム画面から取り除く")
                }
            }
    }
    private func openItem(_ item: HomeItem, source: CGRect) {
        if item.isFolder {
            folderName = item.name
            folderSource = source
            folderProgress = 0
            folderID = item.id
            DispatchQueue.main.async { withAnimation(folderMotion) { folderProgress = 1 } }
        } else if let slot = item.slots.first { open(slot, source: source) }
    }
    private func finishEditing() {
        iconMenu = nil
        cancelLift()
        editing = false
    }
    private func beginHomeLift(_ item: HomeItem, rect: CGRect) {
        guard liftKey == nil else { return }
        liftKey = item.id
        liftFeedback.fire()
        suppressTapUntil = Date().addingTimeInterval(0.8)
        dragOrigin = rect
        dragTranslation = .zero
        if editing { startHomeDrag(item) }
        else {
            withAnimation(.easeOut(duration: 0.16)) {
                iconMenu = IconMenuSelection(item: item, source: rect)
            }
        }
    }
    private func startHomeDrag(_ item: HomeItem) {
        iconMenu = nil
        editing = true
        draggedItem = item
        dragPreview = store.items
    }
    private func updateHomeLift(_ translation: CGSize, metrics: HomeMetrics) {
        guard let item = draggedItem, var preview = dragPreview,
              let from = preview.firstIndex(where: { $0.id == item.id }) else { return }
        dragTranslation = translation
        let point = CGPoint(x: dragOrigin.midX + translation.width, y: dragOrigin.midY + translation.height)
        updateEdgePaging(point, width: metrics.size.width)
        guard let local = (0..<24).first(where: { index in
            let rect = metrics.iconRect(index)
            return CGRect(x: rect.midX - metrics.cell / 2, y: rect.minY - 12,
                          width: metrics.cell, height: metrics.tileHeight + 18).contains(point)
        }) else { hoveredID = nil; hoverCell = nil; return }
        let to = min(preview.count - 1, page * 24 + local)
        if hoverCell != to {
            hoverCell = to
            hoveredID = preview[to].id == item.id ? nil : preview[to].id
            hoverStart = Date()
        }
        guard from != to else { return }
        preview.remove(at: from)
        preview.insert(item, at: to)
        withAnimation(reorderMotion) { dragPreview = preview }
    }
    private func finishMove(_ item: HomeItem) {
        if let target = hoveredID, Date().timeIntervalSince(hoverStart) > 0.65 {
            withAnimation(reorderMotion) { store.merge(source: item.id, target: target) }
        } else if let preview = dragPreview { store.applyOrder(preview) }
        cancelLift()
        suppressTapUntil = Date().addingTimeInterval(0.25)
    }
    private func cancelLift() {
        draggedItem = nil
        liftKey = nil
        folderDraggedSlot = nil
        dragPreview = nil
        folderPreview = nil
        dragTranslation = .zero
        hoveredID = nil
        hoverCell = nil
        edgeDirection = 0
        pagePan = 0
    }
    private func updateEdgePaging(_ point: CGPoint, width: CGFloat) {
        let direction = point.x < 18 ? -1 : (point.x > width - 18 ? 1 : 0)
        guard direction != edgeDirection else { return }
        edgeDirection = direction
        guard direction != 0 else { return }
        let originalPage = page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            guard edgeDirection == direction && draggedItem != nil && page == originalPage else { return }
            page = min(max(0, page + direction), max(0, (store.items.count - 1) / 24))
        }
    }
    private func open(_ slot: Int, source: CGRect) {
        guard !editing && Date() > suppressTapUntil else { return }
        iconMenu = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        appSource = source
        appInteracting = false
        appProgress = 0
        selectedSlot = slot
        DispatchQueue.main.async {
            if reduceMotion { withAnimation(appMotion) { appProgress = 1 } }
            else { appProgress = 1 }
        }
    }
    private func closeApp() {
        appInteracting = false
        if reduceMotion { withAnimation(appMotion) { appProgress = 0 } }
        else { appProgress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            if appProgress == 0 { selectedSlot = nil }
        }
    }
    private func closeFolder() {
        iconMenu = nil
        if let id = folderID { store.rename(id, to: folderName) }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        withAnimation(folderMotion) { folderProgress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            if folderProgress == 0 { folderID = nil }
        }
    }
    private var searchSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 24) {
                    ForEach((1...32).filter { query.isEmpty || String($0).contains(query) }, id: \.self) { slot in
                        Button {
                            showSearch = false
                            open(slot, source: CGRect(x: screenSize.width / 2 - 30, y: screenSize.height / 2 - 30, width: 60, height: 60))
                        } label: {
                            VStack { SlotIcon(slot: slot).frame(width: 60, height: 60); Text("\(slot)") }
                        }.buttonStyle(IconPressStyle()).accessibilityLabel("検索アプリ \(slot)")
                            .contextMenu {
                                if store.hiddenSlots.contains(slot) {
                                    Button("ホーム画面に戻す") {
                                        store.restore(slot)
                                        page = max(0, (store.items.count - 1) / 24)
                                    }
                                }
                            }
                    }
                }.padding()
            }.searchable(text: $query, prompt: "番号を検索")
                .navigationTitle("検索")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        PhotosPicker(selection: $photo, matching: .images) { Image(systemName: "photo") }
                            .accessibilityLabel("背景を写真から選ぶ")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) { Button("完了") { showSearch = false } }
                }
        }.tint(.white)
    }
}

struct SlotPage: View {
    let slot: Int
    let wallpaper: UIImage?
    let safeTop: CGFloat
    let close: () -> Void
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (Bool) -> Void
    var body: some View {
        if slot == 1 {
            PCFileBridgeView(onHome: close)
                .padding(.top, safeTop)
                .padding(.bottom, 16)
                .background(Color(uiColor: .systemGroupedBackground))
                .simultaneousGesture(DragGesture().onChanged { value in
                    if value.startLocation.x < 24 && value.translation.width > abs(value.translation.height) {
                        dragChanged(max(0, value.translation.width))
                    }
                }.onEnded { value in
                    guard value.startLocation.x < 24 else { return }
                    dragEnded(value.translation.width > 100 || value.predictedEndTranslation.width > 220)
                })
        } else {
            ZStack {
                Wallpaper(image: wallpaper)
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 24) {
                    SlotIcon(slot: slot).frame(width: 100, height: 100)
                    Text("\(slot)").font(.system(size: 76, weight: .light, design: .rounded))
                    Text("ページ \(slot)").font(.title3)
                }
                VStack {
                    HStack {
                        Button(action: close) {
                            Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold))
                                .frame(width: 48, height: 48).homeGlass(24)
                        }.accessibilityLabel("ホームへ戻る")
                        Spacer()
                    }.padding(.horizontal, 24).padding(.top, safeTop + 12)
                    Spacer()
                }
            }.foregroundStyle(.white)
                .gesture(DragGesture().onChanged { value in
                    if value.startLocation.x < 40 {
                        dragChanged(max(0, value.translation.width))
                    } else if value.translation.height > abs(value.translation.width) {
                        dragChanged(max(0, value.translation.height))
                    }
                }.onEnded { value in
                    let distance = value.startLocation.x < 40 ? value.translation.width : value.translation.height
                    let predicted = value.startLocation.x < 40 ? value.predictedEndTranslation.width : value.predictedEndTranslation.height
                    dragEnded(distance > 100 || predicted > 220)
                })
        }
    }
}

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

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
    static let initial: [HomeItem] = [
        HomeItem(id: "app-1", name: "1", slots: [1]),
        HomeItem(id: "app-2", name: "2", slots: [2]),
        HomeItem(id: "navigation", name: "ナビゲーション", slots: Array(3...7)),
        HomeItem(id: "utilities", name: "ユーティリティ", slots: Array(8...12))
    ] + (13...32).map { HomeItem(id: "app-\($0)", name: "\($0)", slots: [$0]) }
}

final class HomeStore: ObservableObject {
    @Published var items: [HomeItem] { didSet { save() } }
    init() {
        if let data = UserDefaults.standard.data(forKey: "home-layout-v2"),
           let saved = try? JSONDecoder().decode([HomeItem].self, from: data),
           saved.flatMap(\.slots).sorted() == Array(1...32) {
            items = saved
        } else { items = HomeItem.initial }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: "home-layout-v2")
        }
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
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
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
}

struct GlassSurface: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
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
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
            } else {
                ZStack {
                    LinearGradient(colors: [Color(red: 0.02, green: 0.30, blue: 0.49),
                                            Color(red: 0.06, green: 0.47, blue: 0.71),
                                            Color(red: 0.10, green: 0.16, blue: 0.17)],
                                   startPoint: .top, endPoint: .bottom)
                    Ellipse().fill(Color(red: 0.63, green: 0.57, blue: 0.41))
                        .frame(width: geometry.size.width * 0.52, height: geometry.size.height * 0.56)
                        .position(x: geometry.size.width * 0.47, y: geometry.size.height * 0.57)
                        .blur(radius: geometry.size.width * 0.105)
                    Ellipse().fill(Color(red: 0.80, green: 0.64, blue: 0.35))
                        .frame(width: geometry.size.width * 0.28, height: geometry.size.height * 0.52)
                        .rotationEffect(.degrees(-15))
                        .position(x: geometry.size.width * 0.73, y: geometry.size.height * 0.77)
                        .blur(radius: geometry.size.width * 0.08)
                    Ellipse().fill(Color(red: 0.12, green: 0.16, blue: 0.09))
                        .frame(width: geometry.size.width * 0.72, height: geometry.size.height * 0.35)
                        .position(x: geometry.size.width * 0.30, y: geometry.size.height * 0.91)
                        .blur(radius: geometry.size.width * 0.09)
                }
            }
        }.ignoresSafeArea()
    }
}

struct SlotIcon: View {
    let slot: Int
    var body: some View {
        GeometryReader { geo in
            let hues: [Double] = [0.58, 0.48, 0.35, 0.08, 0.66, 0.97, 0.12, 0.56]
            let hue = hues[(slot - 1) % hues.count]
            ZStack {
                IconContour()
                    .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.64, brightness: 0.98),
                                                 Color(hue: hue, saturation: 0.88, brightness: 0.63)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)).opacity(0.62)
                Text("\(slot)").font(.system(size: geo.size.width * 0.44, weight: .medium, design: .rounded))
            }
            .modifier(IconGlass())
            .overlay(IconContour()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.05), .white.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
        }.aspectRatio(1, contentMode: .fit).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.14), radius: 2, y: 2)
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
    @State private var folderID: String?
    @State private var folderProgress: CGFloat = 0
    @State private var folderSource = CGRect.zero
    @State private var selectedSlot: Int?
    @State private var appProgress: CGFloat = 0
    @State private var appSource = CGRect.zero
    @State private var screenSize = CGSize(width: 390, height: 844)
    @State private var safeTop: CGFloat = 47
    @State private var page = 0
    @State private var showSearch = false
    @State private var query = ""
    @State private var photo: PhotosPickerItem?
    @State private var wallpaper: UIImage?
    @State private var wallpaperError = false
    @State private var folderName = ""
    private var folderMotion: Animation { reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.88) }
    private var appMotion: Animation { reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.45, dampingFraction: 0.90) }
    private var wallpaperURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wallpaper.jpg") }

    var body: some View {
        GeometryReader { geometry in
            let metrics = HomeMetrics(size: geometry.size)
            ZStack(alignment: .topLeading) {
                Wallpaper(image: wallpaper)
                    .blur(radius: reduceMotion ? 0 : 6 * folderProgress)
                homePages(metrics)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.07 * folderProgress + 0.035 * appProgress)
                    .blur(radius: 10 * folderProgress + 7 * appProgress)
                    .opacity(1 - 0.12 * folderProgress)
                    .allowsHitTesting(folderID == nil && selectedSlot == nil)
                    .accessibilityHidden(folderID != nil || selectedSlot != nil)
                if let id = folderID, let item = store.items.first(where: { $0.id == id }) {
                    FolderTransitionLayer(progress: reduceMotion ? 1 : folderProgress,
                                          item: item, source: folderSource, metrics: metrics, name: $folderName,
                                          open: { slot, rect in open(slot, source: rect) }, close: closeFolder,
                                          rename: { store.rename(id, to: folderName) },
                                          extract: { slot in
                        withAnimation(folderMotion) { store.extract(slot, from: id) }
                        if !store.items.contains(where: { $0.id == id && $0.isFolder }) { closeFolder() }
                    })
                    .opacity(reduceMotion ? folderProgress : 1)
                    .allowsHitTesting(selectedSlot == nil)
                    .accessibilityHidden(selectedSlot != nil)
                    .zIndex(2)
                }
                if let slot = selectedSlot {
                    AppTransitionLayer(progress: reduceMotion ? 1 : appProgress, slot: slot,
                                       source: appSource, size: geometry.size, safeTop: safeTop, wallpaper: wallpaper,
                                       close: closeApp,
                                       dragChanged: { amount in appProgress = 1 - min(0.55, max(0, amount / geometry.size.height)) },
                                       dragEnded: { dismiss in
                        if dismiss { closeApp() } else { withAnimation(appMotion) { appProgress = 1 } }
                    })
                    .opacity(reduceMotion ? appProgress : 1).zIndex(3)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .foregroundStyle(.white)
                .onAppear {
                    screenSize = geometry.size
                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = scene.windows.first(where: { $0.isKeyWindow }) {
                        safeTop = window.safeAreaInsets.top
                    }
                }
                .onChange(of: geometry.size) { screenSize = $0 }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showSearch) { searchSheet }
        .task { if let data = try? Data(contentsOf: wallpaperURL) { wallpaper = UIImage(data: data) } }
        .onChange(of: photo) { value in
            Task {
                guard let value else { return }
                do {
                    guard let data = try await value.loadTransferable(type: Data.self),
                          let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else {
                        wallpaperError = true; return
                    }
                    try jpeg.write(to: wallpaperURL, options: .atomic)
                    withAnimation(.easeInOut(duration: 0.25)) { wallpaper = image }
                } catch { wallpaperError = true }
            }
        }
        .alert("背景を読み込めませんでした", isPresented: $wallpaperError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func homePages(_ metrics: HomeMetrics) -> some View {
        ZStack {
            TabView(selection: $page) {
                ForEach(0..<max(1, (store.items.count + 23) / 24), id: \.self) { pageIndex in
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(store.items.dropFirst(pageIndex * 24).prefix(24).enumerated()), id: \.element.id) { index, item in
                            let rect = metrics.iconRect(index)
                            homeTile(item, metrics: metrics, rect: rect)
                                .frame(width: metrics.cell, height: metrics.tileHeight)
                                .position(x: rect.midX, y: rect.minY + metrics.tileHeight / 2)
                                .opacity(folderID == item.id || (selectedSlot.map { item.slots == [$0] } ?? false) ? 0 : 1)
                        }
                    }.frame(width: metrics.size.width, height: metrics.size.height).tag(pageIndex)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never))
            Button { showSearch = true } label: {
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
            if item.isFolder {
                folderName = item.name
                folderSource = rect
                folderProgress = 0
                folderID = item.id
                DispatchQueue.main.async { withAnimation(folderMotion) { folderProgress = 1 } }
            } else if let slot = item.slots.first { open(slot, source: rect) }
        } label: {
            VStack(spacing: metrics.labelGap) {
                Group {
                    if item.isFolder { FolderIcon(item: item) }
                    else { SlotIcon(slot: item.slots[0]) }
                }.frame(width: metrics.icon, height: metrics.icon)
                Text(item.name).font(.system(size: metrics.label)).lineLimit(1)
                    .frame(width: metrics.cell, height: metrics.labelHeight)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            }.frame(width: metrics.cell, height: metrics.tileHeight).contentShape(Rectangle())
        }.buttonStyle(IconPressStyle())
            .accessibilityLabel(item.isFolder ? "\(item.name)、\(item.slots.count)個のアプリ" : "アプリ \(item.name)")
            .onDrag { NSItemProvider(object: item.id as NSString) }
            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { source, _ in
                    guard let source else { return }
                    DispatchQueue.main.async {
                        withAnimation(folderMotion) { store.merge(source: source, target: item.id) }
                    }
                }
                return true
            }
    }
    private func open(_ slot: Int, source: CGRect) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        appSource = source
        appProgress = 0
        selectedSlot = slot
        DispatchQueue.main.async { withAnimation(appMotion) { appProgress = 1 } }
    }
    private func closeApp() {
        withAnimation(appMotion) { appProgress = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
            if appProgress == 0 { selectedSlot = nil }
        }
    }
    private func closeFolder() {
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
                        }.buttonStyle(IconPressStyle())
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


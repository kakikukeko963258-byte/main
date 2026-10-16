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
                RoundedRectangle(cornerRadius: geo.size.width * 0.23, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.64, brightness: 0.98),
                                                 Color(hue: hue, saturation: 0.88, brightness: 0.63)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)).opacity(0.62)
                Text("\(slot)").font(.system(size: geo.size.width * 0.44, weight: .medium, design: .rounded))
            }
            .homeGlass(geo.size.width * 0.23)
            .overlay(RoundedRectangle(cornerRadius: geo.size.width * 0.23, style: .continuous)
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
                .homeGlass(geo.size.width * 0.23)
        }.aspectRatio(1, contentMode: .fit)
    }
}

struct IconPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.89 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

struct HomeView: View {
    @StateObject private var store = HomeStore()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace
    @State private var folderID: String?
    @State private var selectedSlot: Int?
    @State private var page = 0
    @State private var showSearch = false
    @State private var query = ""
    @State private var photo: PhotosPickerItem?
    @State private var wallpaper: UIImage?
    @State private var wallpaperError = false
    @State private var folderName = ""
    @FocusState private var renaming: Bool
    private var motion: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.43, dampingFraction: 0.84) }
    private var wallpaperURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("wallpaper.jpg") }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let icon = width * 0.164
            let label = width * 0.031
            let pitch = min(fullHeight * 0.116, (geometry.size.height - 80) / 6)
            let top = max(12, fullHeight * 0.079 - geometry.safeAreaInsets.top)
            ZStack {
                Wallpaper(image: wallpaper)
                VStack(spacing: 0) {
                    TabView(selection: $page) {
                        ForEach(0..<max(1, (store.items.count + 23) / 24), id: \.self) { index in
                            VStack(spacing: 0) {
                                ForEach(0..<6, id: \.self) { row in
                                    HStack(alignment: .top, spacing: 0) {
                                        ForEach(0..<4, id: \.self) { column in
                                            let offset = index * 24 + row * 4 + column
                                            if offset < store.items.count {
                                                homeTile(store.items[offset], icon: icon, label: label)
                                                    .frame(width: width * 0.231)
                                            } else { Color.clear.frame(width: width * 0.231, height: icon) }
                                        }
                                    }.frame(height: pitch, alignment: .top)
                                }
                                Spacer(minLength: 0)
                            }.padding(.top, top).tag(index)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never))
                    Button { showSearch = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                            Text("検索").font(.system(size: 13, weight: .medium))
                        }.padding(.horizontal, 14).padding(.vertical, 9).homeGlass(30)
                    }.buttonStyle(IconPressStyle())
                        .padding(.bottom, max(18, fullHeight * 0.12 - geometry.safeAreaInsets.bottom))
                }
                .scaleEffect(folderID == nil ? 1 : 0.94)
                .blur(radius: folderID == nil ? 0 : 12)
                .opacity(selectedSlot == nil ? 1 : 0)
                .allowsHitTesting(folderID == nil && selectedSlot == nil)
                .accessibilityHidden(folderID != nil || selectedSlot != nil)

                if let id = folderID, let item = store.items.first(where: { $0.id == id }) {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .onTapGesture { closeFolder() }
                    VStack(spacing: 25) {
                        TextField("フォルダ名", text: $folderName)
                            .font(.system(size: 28, weight: .regular)).multilineTextAlignment(.center)
                            .focused($renaming).submitLabel(.done)
                            .onSubmit { store.rename(id, to: folderName); renaming = false }
                            .accessibilityLabel("フォルダ名")
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 3), spacing: 24) {
                                ForEach(item.slots, id: \.self) { slot in
                                    Button { open(slot) } label: {
                                        VStack(spacing: 6) {
                                            SlotIcon(slot: slot).frame(width: icon, height: icon)
                                            Text("\(slot)").font(.system(size: label))
                                        }
                                    }.buttonStyle(IconPressStyle())
                                        .accessibilityLabel("アプリ \(slot)")
                                        .contextMenu {
                                            Button("フォルダから取り出す", systemImage: "arrow.up.forward.app") {
                                                withAnimation(motion) { store.extract(slot, from: id) }
                                                if !store.items.contains(where: { $0.id == id && $0.isFolder }) { closeFolder() }
                                            }
                                        }
                                }
                            }.padding(26)
                        }.frame(height: width * 0.78, alignment: .top)
                            .homeGlass(42)
                            .matchedGeometryEffect(id: id, in: namespace)
                        Button { closeFolder() } label: {
                            Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 44).homeGlass(22)
                        }.accessibilityLabel("フォルダを閉じる")
                    }.padding(.horizontal, width * 0.10)
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94)))
                        .zIndex(2)
                }
                if let slot = selectedSlot {
                    SlotPage(slot: slot, wallpaper: wallpaper) { withAnimation(motion) { selectedSlot = nil } }
                        .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.86)))
                        .zIndex(3)
                }
            }
            .foregroundStyle(.white)
            .animation(motion, value: folderID)
            .animation(motion, value: selectedSlot)
        }
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
                    withAnimation(motion) { wallpaper = image }
                } catch { wallpaperError = true }
            }
        }
        .alert("背景を読み込めませんでした", isPresented: $wallpaperError) {
            Button("OK", role: .cancel) {}
        }
    }

    private func homeTile(_ item: HomeItem, icon: CGFloat, label: CGFloat) -> some View {
        Button {
            if item.isFolder {
                folderName = item.name
                withAnimation(motion) { folderID = item.id }
            } else if let slot = item.slots.first { open(slot) }
        } label: {
            VStack(spacing: 6) {
                Group {
                    if item.isFolder {
                        FolderIcon(item: item).matchedGeometryEffect(id: item.id, in: namespace, isSource: folderID != item.id)
                    } else { SlotIcon(slot: item.slots[0]) }
                }.frame(width: icon, height: icon)
                Text(item.name).font(.system(size: label)).lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(IconPressStyle())
            .accessibilityLabel(item.isFolder ? "\(item.name)、\(item.slots.count)個のアプリ" : "アプリ \(item.name)")
            .onDrag { NSItemProvider(object: item.id as NSString) }
            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: String.self) { source, _ in
                    guard let source else { return }
                    DispatchQueue.main.async {
                        withAnimation(motion) { store.merge(source: source, target: item.id) }
                    }
                }
                return true
            }
    }
    private func open(_ slot: Int) {
        renaming = false
        withAnimation(motion) { selectedSlot = slot }
    }
    private func closeFolder() {
        if let id = folderID { store.rename(id, to: folderName) }
        renaming = false
        withAnimation(motion) { folderID = nil }
    }
    private var searchSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 24) {
                    ForEach((1...32).filter { query.isEmpty || String($0).contains(query) }, id: \.self) { slot in
                        Button {
                            showSearch = false
                            open(slot)
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
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drag: CGFloat = 0
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
                }.padding(.horizontal, 24).padding(.top, 12)
                Spacer()
            }
        }.foregroundStyle(.white)
            .offset(x: reduceMotion ? 0 : drag)
            .gesture(DragGesture().onChanged { value in
                if value.startLocation.x < 40 { drag = max(0, value.translation.width) }
            }.onEnded { value in
                if value.startLocation.x < 40 && (value.translation.width > 90 || value.predictedEndTranslation.width > 180) { close() }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { drag = 0 }
            })
    }
}


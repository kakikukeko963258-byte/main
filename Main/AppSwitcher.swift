import SwiftUI
import UIKit

final class RecentApps: ObservableObject {
    @Published private(set) var slots: [Int] = []
    @Published private(set) var previews: [Int: UIImage] = [:]
    weak var activeWindow: AppWindowView?
    private let key = "recent-apps-v1"
    private let imageQueue = DispatchQueue(label: "main.switcher-previews", qos: .utility)
    private var imageOrder: [Int] = []
    private var loading = Set<Int>()
    private let previewDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SwitcherPreviews", isDirectory: true)

    init() {
        if ProcessInfo.processInfo.arguments.contains("-reset-home") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        var seen = Set<Int>()
        slots = (UserDefaults.standard.array(forKey: key) as? [Int] ?? []).filter {
            (1...32).contains($0) && seen.insert($0).inserted
        }
        try? FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
    }
    func opened(_ slot: Int) {
        slots = [slot] + slots.filter { $0 != slot }
        UserDefaults.standard.set(slots, forKey: key)
    }
    func capture(_ image: UIImage, slot: Int) {
        guard slots.contains(slot) else { return }
        cache(image, slot: slot)
        let url = previewDirectory.appendingPathComponent("\(slot).jpg")
        imageQueue.async {
            if let data = image.jpegData(compressionQuality: 0.8) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }
    private func cache(_ image: UIImage, slot: Int) {
        previews[slot] = image
        imageOrder = [slot] + imageOrder.filter { $0 != slot }
        imageOrder = Array(imageOrder.prefix(8))
        let retained = Set(imageOrder)
        previews = previews.filter { retained.contains($0.key) }
    }
    func loadPreview(_ slot: Int) {
        guard previews[slot] == nil, !loading.contains(slot) else { return }
        loading.insert(slot)
        let url = previewDirectory.appendingPathComponent("\(slot).jpg")
        imageQueue.async { [weak self] in
            let image = UIImage(contentsOfFile: url.path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading.remove(slot)
                if self.slots.contains(slot), self.previews[slot] == nil, let image { self.cache(image, slot: slot) }
            }
        }
    }
    func terminate(_ slot: Int) {
        slots.removeAll { $0 == slot }
        previews.removeValue(forKey: slot)
        imageOrder.removeAll { $0 == slot }
        let url = previewDirectory.appendingPathComponent("\(slot).jpg")
        imageQueue.async { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.set(slots, forKey: key)
    }
}

struct AppSwitcher: View {
    @ObservedObject var recent: RecentApps
    let active: Int?
    let wallpaper: UIImage?
    let resume: (Int, CGRect) -> Void
    let terminate: (Int) -> Void
    let home: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let card = CGSize(width: size.width * 0.70, height: size.height * 0.68)
            ZStack {
                Color.black.opacity(0.2).ignoresSafeArea()
                    .contentShape(Rectangle()).onTapGesture(perform: home)
                if recent.slots.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 42, weight: .light))
                        Text("最近使ったアプリはありません").font(.headline)
                        Text("番号のページを開くと、ここに表示されます")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }.multilineTextAlignment(.center).padding(24)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: -card.width * 0.50) {
                                ForEach(Array(recent.slots.reversed()), id: \.self) { slot in
                                    GeometryReader { cardGeometry in
                                        let delta = cardGeometry.frame(in: .named("switcherScroll")).midX - size.width / 2
                                        let distance = abs(delta)
                                        let spread = min(1, distance / (card.width * 0.32)) * card.width * 0.22
                                        Color.clear.allowsHitTesting(false)
                                        SwitcherCard(slot: slot, preview: recent.previews[slot], wallpaper: wallpaper,
                                                 size: card, resume: { resume(slot, $0) },
                                                 terminate: { terminate(slot) })
                                            .scaleEffect(reduceMotion ? 1 : max(0.86, 1 - distance / size.width * 0.20))
                                            .offset(x: delta < 0 ? -spread : spread)
                                    }.frame(width: card.width, height: card.height + 38)
                                        .id(slot)
                                        .zIndex(Double(recent.slots.count - (recent.slots.firstIndex(of: slot) ?? 0)))
                                        .onAppear { recent.loadPreview(slot) }
                                }
                            }
                            .switcherTargets()
                            .padding(.horizontal, (size.width - card.width) / 2)
                            .padding(.top, 18).padding(.bottom, 26)
                            .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: home) }
                        }
                        .switcherPaging(stride: card.width * 0.50)
                        .coordinateSpace(name: "switcherScroll")
                        .frame(height: card.height + 86)
                        .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: home) }
                        .onAppear {
                            if let slot = active ?? recent.slots.first {
                                var transaction = Transaction(animation: nil)
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { proxy.scrollTo(slot, anchor: .center) }
                            }
                        }
                    }
                    .offset(y: -size.height * 0.035)
                }
                VStack {
                    Spacer()
                    Button(action: home) {
                        Image(systemName: "house.fill").font(.system(size: 18, weight: .medium))
                            .frame(width: 56, height: 44).contentShape(Rectangle()).homeGlass(22)
                    }.buttonStyle(.plain).accessibilityLabel("ホームへ戻る")
                    Text("左右に切替 · 上にスワイプして終了")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 10)
                }.padding(.bottom, max(38, size.height * 0.06))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: home)
            .foregroundStyle(.white)
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.88), value: recent.slots)
        }.ignoresSafeArea()
    }
}

private struct SwitcherCard: View {
    let slot: Int
    let preview: UIImage?
    let wallpaper: UIImage?
    let size: CGSize
    let resume: (CGRect) -> Void
    let terminate: () -> Void
    @State private var lift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                SlotIcon(slot: slot).frame(width: 28, height: 28)
                Text(slot == 1 ? "PC File Bridge" : "\(slot)")
                    .font(.system(size: 16, weight: .semibold)).lineLimit(1)
            }.padding(.horizontal, 6).allowsHitTesting(false)
            GeometryReader { geometry in
                ZStack {
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                    } else {
                        Wallpaper(image: wallpaper)
                        Color.black.opacity(0.15)
                        Text("開くと画面プレビューが保存されます")
                            .font(.subheadline).multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.7)).padding(24)
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture { resume(geometry.frame(in: .global)) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(slot == 1 ? "最近のアプリ、PC File Bridge" : "最近のアプリ \(slot)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { resume(geometry.frame(in: .global)) }
                .accessibilityAction(named: Text("アプリを終了"), terminate)
            }.frame(width: size.width, height: size.height)
        }
        .frame(width: size.width)
        .offset(y: lift)
        .opacity(1 - min(0.65, Double(-lift / size.height)))
        .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
            if value.translation.height < 0 && abs(value.translation.height) > abs(value.translation.width) {
                lift = value.translation.height
            }
        }.onEnded { value in
            if lift < -70 || (lift < -20 && value.predictedEndTranslation.height < -180) {
                terminate()
            } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8)) { lift = 0 }
            }
        })
    }
}

private extension View {
    @ViewBuilder func switcherPaging(stride: CGFloat) -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetBehavior(GentleCardSnap(stride: stride)) }
        else { self }
    }
    @ViewBuilder func switcherTargets() -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetLayout() }
        else { self }
    }
}

@available(iOS 17.0, *)
private struct GentleCardSnap: ScrollTargetBehavior {
    let stride: CGFloat
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard stride > 0 else { return }
        let projected = target.rect.minX
        let nearest = (projected / stride).rounded() * stride
        // Preserve the system's inertial projection, with only a gentle card bias.
        let strength: CGFloat = abs(context.velocity.dx) < 120 ? 0.65 : 0.16
        target.rect.origin.x = projected + (nearest - projected) * strength
    }
}

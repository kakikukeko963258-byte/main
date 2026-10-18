import SwiftUI
import UIKit

final class RecentApps: ObservableObject {
    @Published private(set) var slots: [Int] = []
    @Published private(set) var previews: [Int: UIImage] = [:]
    private let key = "recent-apps-v1"

    init() {
        if ProcessInfo.processInfo.arguments.contains("-reset-home") {
            UserDefaults.standard.removeObject(forKey: key)
        }
        var seen = Set<Int>()
        slots = (UserDefaults.standard.array(forKey: key) as? [Int] ?? []).filter {
            (1...32).contains($0) && seen.insert($0).inserted
        }
    }
    func opened(_ slot: Int) {
        slots = [slot] + slots.filter { $0 != slot }
        UserDefaults.standard.set(slots, forKey: key)
    }
    func capture(_ image: UIImage, slot: Int) {
        guard slots.contains(slot) else { return }
        previews[slot] = image
        // Persist only the IDs. Actual page images stay on this device in RAM.
        let retained = Set(slots.prefix(8))
        previews = previews.filter { retained.contains($0.key) }
    }
    func terminate(_ slot: Int) {
        slots.removeAll { $0 == slot }
        previews.removeValue(forKey: slot)
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
            let card = CGSize(width: size.width * 0.72, height: size.height * 0.72)
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
                            LazyHStack(spacing: 20) {
                                ForEach(recent.slots, id: \.self) { slot in
                                    SwitcherCard(slot: slot, preview: recent.previews[slot], wallpaper: wallpaper,
                                                 size: card, resume: { resume(slot, $0) },
                                                 terminate: { terminate(slot) })
                                        .id(slot)
                                }
                            }
                            .switcherTargets()
                            .padding(.horizontal, (size.width - card.width) / 2)
                            .padding(.top, 18).padding(.bottom, 26)
                        }
                        .switcherPaging()
                        .frame(height: card.height + 86)
                        .onAppear {
                            if let slot = active ?? recent.slots.first {
                                proxy.scrollTo(slot, anchor: .center)
                            }
                        }
                    }
                    .offset(y: -size.height * 0.025)
                }
                VStack {
                    Spacer()
                    Button(action: home) {
                        Image(systemName: "house.fill").font(.system(size: 18, weight: .medium))
                            .frame(width: 56, height: 40).homeGlass(22)
                    }.buttonStyle(.plain).accessibilityLabel("ホームへ戻る")
                    Text("左右に切替 · 上にスワイプして終了")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        .padding(.top, 10)
                }.padding(.bottom, max(38, size.height * 0.06))
            }
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
            }.padding(.horizontal, 6)
            GeometryReader { geometry in
                ZStack {
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFill()
                    } else {
                        Wallpaper(image: wallpaper)
                        Color.black.opacity(0.15)
                        VStack(spacing: 18) {
                            SlotIcon(slot: slot).frame(width: 72, height: 72)
                            Text(slot == 1 ? "PC File Bridge" : "\(slot)")
                                .font(.system(size: slot == 1 ? 26 : 54, weight: .light, design: .rounded))
                            Text(slot == 1 ? "タップして開く" : "ページ \(slot)").font(.subheadline)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.16), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
                .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
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
    @ViewBuilder func switcherPaging() -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetBehavior(.viewAligned) }
        else { self }
    }
    @ViewBuilder func switcherTargets() -> some View {
        if #available(iOS 17.0, *) { self.scrollTargetLayout() }
        else { self }
    }
}

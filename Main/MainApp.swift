import SwiftUI

@main
struct MainApp: App {
    var body: some Scene {
        WindowGroup { HomeView().preferredColorScheme(.dark) }
    }
}

// Replace the destination for a slot here when adding its future mini app.
struct AppSlot: Identifiable, Hashable {
    let id: Int
    static let all = (1...32).map { AppSlot(id: $0) }
    var colors: [Color] {
        let hues: [Double] = [0.58, 0.36, 0.05, 0.96, 0.68, 0.49, 0.12, 0.61]
        let hue = hues[(id - 1) % hues.count]
        return [Color(hue: hue, saturation: 0.65, brightness: 1),
                Color(hue: hue, saturation: 0.9, brightness: 0.65)]
    }
}

struct Wallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.26),
                                        Color(red: 0.27, green: 0.18, blue: 0.49),
                                        Color(red: 0.80, green: 0.35, blue: 0.39)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse().fill(Color.cyan.opacity(0.4))
                    .frame(width: proxy.size.width * 1.5, height: proxy.size.height * 0.8)
                    .blur(radius: 65).offset(x: -170, y: -230)
                Ellipse().fill(Color.orange.opacity(0.35))
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.6)
                    .blur(radius: 60).offset(x: 150, y: 280)
            }
        }.ignoresSafeArea()
    }
}

struct SlotIcon: View {
    let slot: AppSlot
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.225, style: .continuous)
                    .fill(LinearGradient(colors: slot.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("\(slot.id)")
                    .font(.system(size: geometry.size.width * 0.43, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.2), radius: 3, y: 3)
    }
}

struct HomeView: View {
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let gap: CGFloat = 9
                let rowHeight = max(1, (geometry.size.height - 54 - gap * 7) / 8)
                let iconSize = min(62, max(1, rowHeight - 17), (geometry.size.width - 80) / 4)
                ZStack {
                    Wallpaper()
                    VStack(spacing: 0) {
                        VStack(spacing: gap) {
                            ForEach(0..<8, id: \.self) { row in
                                HStack(spacing: 0) {
                                    ForEach(0..<4, id: \.self) { column in
                                        let slot = AppSlot.all[row * 4 + column]
                                        NavigationLink(value: slot) {
                                            VStack(spacing: 3) {
                                                SlotIcon(slot: slot).frame(width: iconSize, height: iconSize)
                                                Text("\(slot.id)").font(.system(size: 11))
                                                    .foregroundStyle(.white)
                                                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                                            }
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(IconPressStyle())
                                        .accessibilityLabel("アプリ \(slot.id)")
                                        .accessibilityHint("\(slot.id)番のページを開く")
                                        .accessibilityIdentifier("slot-\(slot.id)")
                                    }
                                }.frame(height: rowHeight)
                            }
                        }.padding(.horizontal, 16)
                        Spacer(minLength: 0)
                        HStack(spacing: 7) {
                            Circle().fill(.white).frame(width: 6, height: 6)
                        }.frame(height: 34)
                    }.padding(.top, 8)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: AppSlot.self) { slot in
                SlotPage(slot: slot)
            }
        }.tint(.white)
    }
}

struct IconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SlotPage: View {
    let slot: AppSlot
    var body: some View {
        ZStack {
            Wallpaper()
            VStack(spacing: 24) {
                SlotIcon(slot: slot).frame(width: 100, height: 100)
                Text("\(slot.id)").font(.system(size: 72, weight: .light, design: .rounded))
                Text("ページ \(slot.id)").font(.title3)
            }.foregroundStyle(.white)
        }
        .navigationTitle("\(slot.id)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

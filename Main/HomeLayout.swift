import SwiftUI

// Measurements from the supplied 947 x 2048 reference, in full-screen coordinates.
// The source file is higher resolution; all values are normalized to this canvas.
struct HomeMetrics {
    let size: CGSize
    var icon: CGFloat { size.width * 156 / 947 }
    var cell: CGFloat { size.width * 219 / 947 }
    var label: CGFloat { size.width * 29 / 947 }
    var labelHeight: CGFloat { size.width * 34 / 947 }
    var labelGap: CGFloat { size.width * 13 / 947 }
    var tileHeight: CGFloat { icon + labelGap + labelHeight }
    var folderRect: CGRect {
        CGRect(x: size.width * 0.121, y: size.height * 0.2955,
               width: size.width * 0.758, height: size.height * 0.410)
    }
    func iconRect(_ index: Int) -> CGRect {
        let centers: [CGFloat] = [145.5, 364.5, 583, 801]
        return CGRect(x: size.width * centers[index % 4] / 947 - icon / 2,
                      y: size.height * (163 + 238 * CGFloat((index % 24) / 4)) / 2048,
                      width: icon, height: icon)
    }
    func folderIconRect(_ index: Int) -> CGRect {
        let panel = folderRect
        return CGRect(x: size.width * (0.269 + 0.231 * CGFloat(index % 3)) - icon / 2,
                      y: panel.minY + size.height * 0.031 + CGFloat(index / 3) * size.height * 0.120,
                      width: icon, height: icon)
    }
    func previewRect(_ index: Int, source: CGRect) -> CGRect {
        let side = source.width * 0.20
        return CGRect(x: source.minX + source.width * 0.14 + CGFloat(index % 3) * source.width * 0.245,
                      y: source.minY + source.height * 0.14 + CGFloat(index / 3) * source.height * 0.245,
                      width: side, height: side)
    }
}

// A fourth-order superellipse follows the measured Photos icon edge:
// 8 reference pixels below the top, the edge is about 17 pixels from the left.
// A circular corner or an arbitrary glass corner radius does not follow this edge.
struct IconContour: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for step in 0...128 {
            let angle = Double(step) * .pi * 2 / 128
            let c = cos(angle), s = sin(angle)
            let x = copysign(sqrt(abs(c)), c)
            let y = copysign(sqrt(abs(s)), s)
            let point = CGPoint(x: rect.midX + CGFloat(x) * rect.width / 2,
                                y: rect.midY + CGFloat(y) * rect.height / 2)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct IconGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: IconContour())
        } else {
            content.background(.ultraThinMaterial, in: IconContour())
        }
    }
}

struct WindowContour: Shape {
    let corner: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(corner, min(rect.width, rect.height) / 2)
        guard r > 0.01 else { return Path(rect) }
        var path = Path()
        let centers = [CGPoint(x: rect.maxX - r, y: rect.minY + r),
                       CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                       CGPoint(x: rect.minX + r, y: rect.maxY - r),
                       CGPoint(x: rect.minX + r, y: rect.minY + r)]
        for quadrant in 0..<4 {
            for step in 0...32 {
                let angle = Double(quadrant - 1) * .pi / 2 + Double(step) * .pi / 64
                let c = cos(angle), s = sin(angle)
                let point = CGPoint(x: centers[quadrant].x + CGFloat(copysign(sqrt(abs(c)), c)) * r,
                                    y: centers[quadrant].y + CGFloat(copysign(sqrt(abs(s)), s)) * r)
                if quadrant == 0 && step == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }
}

func interpolatedRect(_ from: CGRect, _ to: CGRect, _ t: CGFloat) -> CGRect {
    CGRect(x: from.minX + (to.minX - from.minX) * t,
           y: from.minY + (to.minY - from.minY) * t,
           width: from.width + (to.width - from.width) * t,
           height: from.height + (to.height - from.height) * t)
}

struct FolderTransitionLayer: View, Animatable {
    var progress: CGFloat
    let item: HomeItem
    let source: CGRect
    let metrics: HomeMetrics
    @Binding var name: String
    var open: (Int, CGRect) -> Void
    var close: () -> Void
    var editing: Bool
    var beginEditing: () -> Void
    var draggingSlot: Int?
    var dragChanged: (Int, CGSize) -> Void
    var dragEnded: (Int, CGSize) -> Void
    var rename: () -> Void
    var extract: (Int) -> Void
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let t = min(1, max(0, progress))
        let panel = interpolatedRect(source, metrics.folderRect, t)
        let nameOpacity = min(1, max(0, (t - 0.55) / 0.45))
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle()).onTapGesture(perform: close)
            Color.clear.frame(width: panel.width, height: panel.height)
                .homeGlass(source.width * 0.24 + (metrics.size.width * 0.10 - source.width * 0.24) * t)
                .position(x: panel.midX, y: panel.midY)
            // Pages retain the 3 x 3 layout used by SpringBoard folders.
            if item.slots.count <= 9 {
                ForEach(Array(item.slots.enumerated()), id: \.element) { index, slot in
                    let rect = interpolatedRect(metrics.previewRect(index, source: source), metrics.folderIconRect(index), t)
                    folderButton(slot, rect: rect, opacity: nameOpacity)
                }
            } else {
                TabView {
                    ForEach(0..<((item.slots.count + 8) / 9), id: \.self) { page in
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(item.slots.dropFirst(page * 9).prefix(9).enumerated()), id: \.element) { index, slot in
                                let rect = metrics.folderIconRect(index).offsetBy(dx: -metrics.folderRect.minX, dy: -metrics.folderRect.minY)
                                folderButton(slot, rect: rect, opacity: nameOpacity, page: page)
                            }
                        }.frame(width: metrics.folderRect.width, height: metrics.folderRect.height)
                    }
                }.tabViewStyle(.page(indexDisplayMode: .automatic))
                    .frame(width: metrics.folderRect.width, height: metrics.folderRect.height)
                    .position(x: panel.midX, y: panel.midY)
                    .opacity(nameOpacity)
            }
            TextField("フォルダ名", text: $name)
                .font(.system(size: metrics.size.width * 32 / 390, weight: .semibold))
                .multilineTextAlignment(.center).submitLabel(.done)
                .onSubmit(rename).accessibilityLabel("フォルダ名")
                .frame(width: metrics.size.width * 0.86)
                .position(x: metrics.size.width / 2, y: metrics.size.height * 0.230)
                .opacity(nameOpacity)
            // Invisible accessibility target; visually the original closes by tapping outside.
            Button(action: close) { Color.clear.frame(width: 64, height: 64).contentShape(Rectangle()) }
                .accessibilityLabel("フォルダを閉じる")
                .position(x: metrics.size.width / 2, y: metrics.size.height * 0.82)
        }.frame(width: metrics.size.width, height: metrics.size.height)
    }
    private func folderButton(_ slot: Int, rect: CGRect, opacity: CGFloat, page: Int = 0) -> some View {
        Button { open(slot, metrics.folderIconRect((item.slots.firstIndex(of: slot) ?? 0) % 9)) } label: {
            ZStack(alignment: .top) {
                SlotIcon(slot: slot).frame(width: rect.width, height: rect.height)
                Text("\(slot)").font(.system(size: metrics.label))
                    .frame(width: metrics.cell, height: metrics.labelHeight)
                    .offset(y: rect.height + metrics.labelGap).opacity(opacity)
            }.frame(width: rect.width, height: rect.height)
        }.buttonStyle(IconPressStyle()).accessibilityLabel("アプリ \(slot)")
            .opacity(draggingSlot == slot ? 0 : 1)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.35)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { value in
                    switch value {
                    case .first(true): beginEditing()
                    case .second(true, let drag):
                        beginEditing()
                        if let drag { dragChanged(slot, drag.translation) }
                    default: break
                    }
                }.onEnded { value in
                    if case .second(true, let drag) = value, let drag { dragEnded(slot, drag.translation) }
                })
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { extract(slot) } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black).frame(width: 24, height: 24)
                            .background(.white.opacity(0.9), in: Circle())
                    }.buttonStyle(.plain).offset(x: -7, y: -7)
                        .accessibilityLabel("アプリ \(slot) をフォルダから取り出す")
                }
            }
            .position(x: rect.midX, y: rect.midY)
    }
}

struct AppTransitionLayer: View, Animatable {
    var progress: CGFloat
    let slot: Int
    let source: CGRect
    let size: CGSize
    let safeTop: CGFloat
    let wallpaper: UIImage?
    let close: () -> Void
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (Bool) -> Void
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    var body: some View {
        let t = min(1, max(0, progress))
        let rect = interpolatedRect(source, CGRect(origin: .zero, size: size), t)
        let radius = source.width * 0.5 * (1 - t)
        ZStack {
            SlotPage(slot: slot, wallpaper: wallpaper, safeTop: safeTop, close: close,
                     dragChanged: dragChanged, dragEnded: dragEnded)
                .frame(width: size.width, height: size.height)
                .scaleEffect(x: rect.width / size.width, y: rect.height / size.height)
                .frame(width: rect.width, height: rect.height)
                .opacity(min(1, max(0, (t - 0.12) / 0.22)))
            SlotIcon(slot: slot).frame(width: rect.width, height: rect.height)
                .opacity(1 - min(1, t / 0.24)).allowsHitTesting(false)
        }.frame(width: rect.width, height: rect.height)
            .clipShape(WindowContour(corner: radius))
            .position(x: rect.midX, y: rect.midY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

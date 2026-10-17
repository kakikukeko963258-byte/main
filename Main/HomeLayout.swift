import SwiftUI

// Measurements from the supplied 947 x 2048 reference, in full-screen coordinates.
// The source file is higher resolution; all values are normalized to this canvas.
struct HomeMetrics {
    let size: CGSize
    var homeOffset: CGFloat = 0
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
                      y: size.height * (163 + 238 * CGFloat((index % 24) / 4)) / 2048 + homeOffset,
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
    var blankTap: () -> Void
    var prepareLift: () -> Void
    var beginLift: (Int) -> Void
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
            Color.clear.contentShape(Rectangle()).onTapGesture { if editing { blankTap() } else { close() } }
            Color.clear.frame(width: panel.width, height: panel.height)
                .homeGlass(source.width * 0.24 + (metrics.size.width * 0.10 - source.width * 0.24) * t)
                .opacity(item.isFolder ? 1 : t)
                .onTapGesture(perform: blankTap)
                .position(x: panel.midX, y: panel.midY)
            // Pages retain the 3 x 3 layout used by SpringBoard folders.
            if item.slots.count <= 9 {
                ForEach(Array(item.slots.enumerated()), id: \.element) { index, slot in
                    let preview = item.isFolder ? metrics.previewRect(index, source: source) : source
                    let rect = interpolatedRect(preview, metrics.folderIconRect(index), t)
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
                .opacity(draggingSlot == slot ? 0 : 1)
                .modifier(EditingWiggle(active: editing && draggingSlot != slot, seed: slot))
        }.buttonStyle(IconPressStyle()).accessibilityLabel("アプリ \(slot)")
            .overlay {
                IconTouchSurface(
                    exclusion: editing ? CGRect(x: -7, y: -7, width: 24, height: 24) : nil,
                    prepare: prepareLift,
                    tap: { open(slot, metrics.folderIconRect((item.slots.firstIndex(of: slot) ?? 0) % 9)) },
                    began: { beginLift(slot) },
                    changed: { dragChanged(slot, $0) },
                    ended: { dragEnded(slot, $0) },
                    cancelled: { dragEnded(slot, .zero) })
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button { extract(slot) } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black).frame(width: 24, height: 24)
                            .background(.white.opacity(0.9), in: Circle())
                    }.buttonStyle(.plain).opacity(draggingSlot == slot ? 0 : 1).offset(x: -7, y: -7)
                        .accessibilityLabel("アプリ \(slot) をフォルダから取り出す")
                }
            }
            .position(x: rect.midX, y: rect.midY)
    }
}

// Keep the page at its final layout size. UIKit animates a single captured surface;
// neither SwiftUI layout nor the live glass back button runs on every animation frame.
struct AppTransitionLayer: UIViewControllerRepresentable {
    var progress: CGFloat
    let animated: Bool
    let interactive: Bool
    let slot: Int
    let source: CGRect
    let size: CGSize
    let safeTop: CGFloat
    let wallpaper: UIImage?
    let close: () -> Void
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (Bool) -> Void

    func makeUIViewController(context: Context) -> AppWindowController {
        let page = SlotPage(slot: slot, wallpaper: wallpaper, safeTop: safeTop,
                            close: close, dragChanged: dragChanged, dragEnded: dragEnded)
        return AppWindowController(page: page, size: size, source: source)
    }
    func updateUIViewController(_ controller: AppWindowController, context: Context) {
        controller.windowView.setProgress(progress, animated: animated && !interactive)
    }
}

// The embedded bridge uses navigation, keyboard and document pickers. Keep its
// hosting controller in UIKit's containment tree while animating the same surface.
final class AppWindowController: UIViewController {
    let windowView: AppWindowView

    init(page: SlotPage, size: CGSize, source: CGRect) {
        windowView = AppWindowView(page: page, size: size, source: source)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func loadView() {
        addChild(windowView.host)
        view = windowView
        windowView.host.didMove(toParent: self)
    }
}

final class AppWindowView: UIView {
    fileprivate let host: UIHostingController<SlotPage>
    private let surface = UIView()
    private let icon = UIImageView()
    private let contourMask = CAShapeLayer()
    private let pageSize: CGSize
    private let source: CGRect
    private var capture: UIView?
    private var displayLink: CADisplayLink?
    private var currentProgress: CGFloat = 0
    private var targetProgress: CGFloat = 0
    private var animationFrom: CGFloat = 0
    private var animationStarted: CFTimeInterval = 0
    private var animationDuration: CFTimeInterval = 0.46

    init(page: SlotPage, size: CGSize, source: CGRect) {
        host = UIHostingController(rootView: page)
        pageSize = size
        self.source = source
        super.init(frame: CGRect(origin: .zero, size: size))
        backgroundColor = .clear
        surface.frame = bounds
        contourMask.frame = surface.bounds
        contourMask.fillColor = UIColor.black.cgColor
        contourMask.contentsScale = UIScreen.main.scale
        addSubview(surface)
        host.view.backgroundColor = .clear
        host.view.frame = surface.bounds
        host.view.insetsLayoutMarginsFromSafeArea = false
        if #available(iOS 16.4, *) { host.safeAreaRegions = [] }
        surface.addSubview(host.view)
        icon.image = IconArtwork.image(page.slot)
        // Both axes follow the evolving window. Preserve neither the square
        // source aspect ratio nor a uniform scale during the crossfade.
        icon.contentMode = .scaleToFill
        icon.frame = surface.bounds
        icon.isUserInteractionEnabled = false
        surface.addSubview(icon)
        apply(0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { displayLink?.invalidate() }

    func setProgress(_ progress: CGFloat, animated: Bool) {
        let t = min(1, max(0, progress))
        if animated && t == targetProgress && displayLink != nil { return }
        if t == currentProgress && displayLink == nil { targetProgress = t; return }
        displayLink?.invalidate()
        displayLink = nil
        targetProgress = t
        if capture == nil {
            host.view.layoutIfNeeded()
            if let snapshot = host.view.snapshotView(afterScreenUpdates: true) {
                snapshot.frame = CGRect(origin: .zero, size: pageSize)
                let blend = min(1, max(0, (currentProgress - 0.04) / 0.26))
                snapshot.alpha = blend * blend * (3 - 2 * blend)
                surface.insertSubview(snapshot, belowSubview: icon)
                capture = snapshot
                host.view.isHidden = true
            }
        }
        if animated {
            animationFrom = currentProgress
            animationStarted = CACurrentMediaTime()
            animationDuration = 0.46 * max(0.38, Double(abs(t - currentProgress)))
            let clock = WindowAnimationClock(owner: self)
            let link = CADisplayLink(target: clock, selector: #selector(WindowAnimationClock.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
            displayLink = link
            link.add(to: .main, forMode: .common)
        } else {
            currentProgress = t
            apply(t)
            finishIfExpanded()
        }
    }
    fileprivate func advance(_ timestamp: CFTimeInterval) {
        let u = min(1, max(0, (timestamp - animationStarted) / animationDuration))
        // Fast expansion followed by a gentle settle, using the same curve in
        // reverse for closing. Only cached surfaces and their mask are updated.
        let eased = CGFloat(1 - pow(1 - u, 3.3))
        currentProgress = animationFrom + (targetProgress - animationFrom) * eased
        apply(currentProgress)
        if u >= 1 {
            displayLink?.invalidate()
            displayLink = nil
            currentProgress = targetProgress
            apply(currentProgress)
            finishIfExpanded()
        }
    }
    private func finishIfExpanded() {
        guard currentProgress == 1 else { return }
        host.view.isHidden = false
        capture?.removeFromSuperview()
        capture = nil
    }
    private func apply(_ t: CGFloat) {
        let rect = interpolatedRect(source, CGRect(origin: .zero, size: pageSize), t)
        let sx = max(0.001, rect.width / pageSize.width)
        let sy = max(0.001, rect.height / pageSize.height)
        // At zero, half the icon width yields the exact fourth-order icon
        // contour. As the window lengthens, its corners become local corners
        // rather than an enlarged ellipse stretching over the whole screen.
        let corner = source.width / 2 + (pageSize.width * 0.12 - source.width / 2) * t
        var inverseScale = CGAffineTransform(scaleX: 1 / sx, y: 1 / sy)
        let path = WindowContour(corner: corner).path(in: CGRect(origin: .zero, size: rect.size)).cgPath
        let blend = min(1, max(0, (t - 0.04) / 0.26))
        let pageAlpha = blend * blend * (3 - 2 * blend)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.transform = CGAffineTransform(scaleX: sx, y: sy)
        surface.center = CGPoint(x: rect.midX, y: rect.midY)
        contourMask.path = path.copy(using: &inverseScale)
        surface.layer.mask = t >= 0.9999 ? nil : contourMask
        icon.alpha = 1 - pageAlpha
        capture?.alpha = pageAlpha
        CATransaction.commit()
    }
}

// CADisplayLink retains its target; the weak owner keeps the transition view
// releasable when its page is removed or an interactive transition is cancelled.
private final class WindowAnimationClock: NSObject {
    weak var owner: AppWindowView?
    init(owner: AppWindowView) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.advance(link.timestamp) }
}

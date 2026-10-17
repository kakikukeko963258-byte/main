import SwiftUI
import UIKit

// Keep UIKit's recognized touch attached to the same view while a SwiftUI menu
// is inserted or dismissed. Coordinates stay in the window when tiles reorder.
struct IconTouchSurface: UIViewRepresentable {
    var exclusion: CGRect? = nil
    let prepare: () -> Void
    let tap: () -> Void
    let began: () -> Void
    let changed: (CGSize) -> Void
    let ended: (CGSize) -> Void
    let cancelled: () -> Void

    func makeUIView(context: Context) -> IconTouchView { IconTouchView() }
    func updateUIView(_ view: IconTouchView, context: Context) {
        view.exclusion = exclusion
        view.prepare = prepare
        view.tap = tap
        view.began = began
        view.changed = changed
        view.ended = ended
        view.cancelled = cancelled
    }
}

final class IconTouchView: UIView, UIGestureRecognizerDelegate {
    var exclusion: CGRect?
    var prepare: () -> Void = {}
    var tap: () -> Void = {}
    var began: () -> Void = {}
    var changed: (CGSize) -> Void = { _ in }
    var ended: (CGSize) -> Void = { _ in }
    var cancelled: () -> Void = {}
    private var origin = CGPoint.zero
    private var tracking = false

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        isAccessibilityElement = false
        let press = UILongPressGestureRecognizer(target: self, action: #selector(press(_:)))
        press.minimumPressDuration = 0.22
        press.allowableMovement = 12
        press.delegate = self
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        singleTap.require(toFail: press)
        singleTap.delegate = self
        addGestureRecognizer(press)
        addGestureRecognizer(singleTap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let exclusion, exclusion.insetBy(dx: -2, dy: -2).contains(point) { return false }
        return super.point(inside: point, with: event)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        prepare()
        super.touchesBegan(touches, with: event)
    }
    @objc private func tapped() { tap() }
    @objc private func press(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: window)
        let translation = CGSize(width: point.x - origin.x, height: point.y - origin.y)
        switch recognizer.state {
        case .began:
            origin = point
            tracking = true
            began()
        case .changed:
            changed(translation)
        case .ended:
            tracking = false
            ended(translation)
        case .cancelled, .failed:
            if tracking { tracking = false; cancelled() }
        default: break
        }
    }
}

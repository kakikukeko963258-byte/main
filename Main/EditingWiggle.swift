import SwiftUI

// Only the visual label switches branches; the button and its active drag gesture
// stay mounted. Removing the animated branch discards repeatForever completely.
struct EditingWiggle: ViewModifier {
    let active: Bool
    let seed: Int
    var anchor: UnitPoint = .center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @ViewBuilder
    func body(content: Content) -> some View {
        if active && !reduceMotion && scenePhase == .active {
            content.modifier(ActiveIconRock(seed: seed, anchor: anchor))
        } else {
            content.transaction { $0.animation = nil }
        }
    }
}

private struct ActiveIconRock: ViewModifier {
    let seed: Int
    let anchor: UnitPoint
    @EnvironmentObject private var clock: EditingClock
    private var angle: Double { seed.isMultiple(of: 2) ? 1.6 : -1.6 }
    func body(content: Content) -> some View {
        content.rotationEffect(.degrees(clock.rocking ? angle : -angle), anchor: anchor)
    }
}

// One low-frequency clock keeps folders and icons on the same phase and curve.
final class EditingClock: ObservableObject {
    @Published var rocking = false
    private var timer: Timer?
    func setActive(_ active: Bool) {
        timer?.invalidate(); timer = nil
        guard active else { rocking = false; return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.15)) { self.rocking.toggle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    deinit { timer?.invalidate() }
}

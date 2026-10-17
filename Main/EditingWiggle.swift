import SwiftUI

// Repeating transform animation: no timers, layout changes, or per-frame state.
struct EditingWiggle: ViewModifier {
    let active: Bool
    let seed: Int
    var anchor: UnitPoint = .center
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var rocking = false

    private var enabled: Bool { active && !reduceMotion && scenePhase == .active }
    private var angle: Double { seed.isMultiple(of: 2) ? 1.4 : -1.4 }
    private var motion: Animation {
        enabled
            ? .easeInOut(duration: 0.13 + Double(seed % 3) * 0.012).repeatForever(autoreverses: true)
            : .easeOut(duration: 0.10)
    }
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(enabled ? (rocking ? angle : -angle) : 0), anchor: anchor)
            .animation(motion, value: rocking)
            .onAppear { rocking = enabled }
            .onChange(of: enabled) { rocking = $0 }
    }
}

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
    @State private var rocking = false
    private var angle: Double { seed.isMultiple(of: 2) ? 1.6 : -1.6 }
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(rocking ? angle : -angle), anchor: anchor)
            .onAppear {
                // Keep folders and standalone icons on the same gentle rhythm.
                withAnimation(.easeInOut(duration: 0.15)
                    .repeatForever(autoreverses: true)) { rocking = true }
            }
    }
}

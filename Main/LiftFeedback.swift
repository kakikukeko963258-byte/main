import UIKit
import SwiftUI

// Prepared at touch-down, fired once when the long press is recognized.
// Movement callbacks never allocate generators or trigger repeated vibration.
final class LiftFeedback: ObservableObject {
    private let generator = UIImpactFeedbackGenerator(style: .medium)
    func prepare() { generator.prepare() }
    func fire() { generator.impactOccurred(intensity: 0.8) }
}

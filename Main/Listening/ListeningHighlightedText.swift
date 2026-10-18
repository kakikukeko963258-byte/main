import SwiftUI
import UIKit

/// Word positions are measured against the bundled Google narration, in audio seconds.
/// Using AVAudioPlayer.currentTime keeps highlighting aligned when seeking or changing speed.
struct ListeningHighlightedText: UIViewRepresentable {
    let text: String
    let words: [ListeningWordTiming]
    let active: Int?
    let identity: String
    let seek: (Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = false
        view.backgroundColor = .secondarySystemGroupedBackground
        view.textContainerInset = UIEdgeInsets(top: 18, left: 14, bottom: 30, right: 14)
        view.adjustsFontForContentSizeCategory = true
        view.accessibilityIdentifier = "listening-reading-text"
        view.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:))))
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.words = words
        coordinator.seek = seek
        if coordinator.identity != identity || view.text != text {
            coordinator.identity = identity
            coordinator.range = nil
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 8
            view.attributedText = NSAttributedString(string: text, attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title3),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ])
            view.setContentOffset(.zero, animated: false)
        }
        let word = active.flatMap { words.indices.contains($0) ? words[$0] : nil }
        view.accessibilityValue = word.flatMap {
            NSMaxRange(NSRange(location: $0.location, length: $0.length)) <= (text as NSString).length
                ? (text as NSString).substring(with: NSRange(location: $0.location, length: $0.length)) : nil
        } ?? ""
        let next = word.map { NSRange(location: $0.location, length: $0.length) }
        guard next != coordinator.range else { return }
        if let old = coordinator.range, NSMaxRange(old) <= view.textStorage.length {
            view.textStorage.removeAttribute(.backgroundColor, range: old)
            view.textStorage.addAttribute(.foregroundColor, value: UIColor.label, range: old)
        }
        coordinator.range = next
        if let next = next, NSMaxRange(next) <= view.textStorage.length {
            view.textStorage.addAttributes([.backgroundColor: UIColor.systemYellow,
                                           .foregroundColor: UIColor.black], range: next)
            // Don't pull the page away while the reader is deliberately scrolling.
            if !view.isDragging && !view.isDecelerating {
                view.scrollRangeToVisible(next)
            }
        }
    }

    final class Coordinator: NSObject {
        var identity = ""
        var range: NSRange?
        var words: [ListeningWordTiming] = []
        var seek: ((Double) -> Void)?

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? UITextView,
                  let position = view.closestPosition(to: gesture.location(in: view)) else { return }
            let character = view.offset(from: view.beginningOfDocument, to: position)
            if let word = words.first(where: { character >= $0.location && character < $0.location + $0.length }) {
                seek?(word.start)
            }
        }
    }
}

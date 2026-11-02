import Foundation
import CoreImage
import ImageIO

@main
struct RawDeveloperChecks {
    @MainActor static func main() async throws {
        let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
        var neutral = RawAdjustments(); neutral.look = "Neutral"; neutral.grain = 0
        let first = try RawDeveloper.image(fixture, adjustments: neutral)
        precondition(first.extent.width * first.extent.height > 5_000_000, "Unexpected DNG dimensions: \(first.extent)")
        let original = try RawDeveloper.jpeg(first)
        var changed = neutral; changed.look = "Cinema"; changed.exposure = 1.5; changed.grain = 0.4
        let rendered = try RawDeveloper.jpeg(RawDeveloper.image(fixture, adjustments: changed))
        precondition(original != rendered, "Adjustments did not change pixels")
        let repeated = try RawDeveloper.jpeg(RawDeveloper.image(fixture, adjustments: changed))
        precondition(repeated == rendered, "Unstable grain")
        let reduced = try RawDeveloper.image(fixture, adjustments: neutral, maxSide: 128)
        precondition(max(reduced.extent.width, reduced.extent.height) <= 130, "Preview not reduced")
        let library = RawPhotoLibrary()
        let data = try Data(contentsOf: fixture)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            library.add(data: data, format: "RAW") { done.resume() }
        }
        guard let shot = library.shots.first else { fatalError("RAW was not saved") }
        defer {
            for suffix in ["dng", "jpg", "json"] {
                try? FileManager.default.removeItem(at: library.root.appendingPathComponent(shot.stem + "." + suffix))
            }
        }
        precondition(library.error == nil, library.error ?? "")
        library.save(shot, adjustments: changed)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            library.queue.async { DispatchQueue.main.async { done.resume() } }
        }
        precondition(library.error == nil, library.error ?? "")
        let reload = RawPhotoLibrary()
        guard let saved = reload.shots.first(where: { $0.id == shot.id }) else { fatalError("Saved metadata missing") }
        precondition(saved.adjustments == changed, "Edits lost after reload")
        let originalAfterEditing = try Data(contentsOf: library.original(saved))
        precondition(originalAfterEditing == data, "Original changed during editing")
        for kind in ["DNG", "JPEG", "HEIC"] {
            let url = await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
                library.export(saved, kind: kind) { done.resume(returning: $0) }
            }
            guard let url else { fatalError(library.error ?? "Export failed") }
            defer { try? FileManager.default.removeItem(at: url) }
            if kind == "DNG" { let exported = try Data(contentsOf: url); precondition(exported == data, "DNG export changed original") }
            else { precondition(CGImageSourceCreateWithURL(url as CFURL, nil) != nil, "Unreadable export") }
        }
        print("RAW checks passed: DNG development, editing, stable grain, preview scale, durable metadata, unchanged original, DNG/JPEG/HEIC export")
    }
}

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
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("RawChecks-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let library = RawPhotoLibrary(directory: base.appendingPathComponent("source"))
        let data = try Data(contentsOf: fixture)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            library.add(data: data, format: "RAW", metadata: RawCaptureMetadata(width: 8064, height: 6048)) { done.resume() }
        }
        guard let shot = library.shots.first else { fatalError("RAW was not saved") }
        defer {
            for suffix in ["dng", "jpg", "json"] {
                try? FileManager.default.removeItem(at: library.root.appendingPathComponent(shot.stem + "." + suffix))
            }
        }
        precondition(library.error == nil, library.error ?? "")
        precondition((shot.capture?.megapixels ?? 0) < 14 && (shot.capture?.megapixels ?? 0) > 10, "Requested 48MP incorrectly reported as saved resolution")
        library.save(shot, adjustments: changed)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            library.queue.async { DispatchQueue.main.async { done.resume() } }
        }
        precondition(library.error == nil, library.error ?? "")
        let reload = RawPhotoLibrary(directory: library.root)
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
        let smallURL = await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
            library.export(saved, kind: "JPEG", maxSide: 1024) { done.resume(returning: $0) }
        }
        guard let smallURL, let smallSource = CGImageSourceCreateWithURL(smallURL as CFURL, nil),
              let smallProperties = CGImageSourceCopyPropertiesAtIndex(smallSource, 0, nil) as? [String: Any] else { fatalError("Sized export missing") }
        defer { try? FileManager.default.removeItem(at: smallURL) }
        let smallWidth = (smallProperties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
        let smallHeight = (smallProperties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
        precondition(max(smallWidth, smallHeight) == 1024, "Export size is not the requested 1024 pixels")
        if let inputSource = CGImageSourceCreateWithURL(fixture as CFURL, nil), let inputProperties = CGImageSourceCopyPropertiesAtIndex(inputSource, 0, nil) as? [String: Any],
           let inputExif = inputProperties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let expected = inputExif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            let outputExif = smallProperties[kCGImagePropertyExifDictionary as String] as? [String: Any]
            precondition(outputExif?[kCGImagePropertyExifDateTimeOriginal as String] as? String == expected, "Capture date lost on export")
        }
        precondition(smallProperties[kCGImagePropertyGPSDictionary as String] == nil, "Location should be excluded by default")
        var cropped = changed
        cropped.cropAspect = "1:1"; cropped.cropZoom = 1.2; cropped.rotation = 1; cropped.flipH = true; cropped.cropX = 0.2
        let square = try RawDeveloper.image(fixture, adjustments: cropped, maxSide: 256)
        precondition(abs(square.extent.width - square.extent.height) < 1 && abs(square.extent.width - 256) < 1, "Crop or export dimensions incorrect: \(square.extent)")
        let oldRecipe = try JSONDecoder().decode(RawAdjustments.self, from: Data("{\"exposure\":0.5,\"warmth\":0,\"saturation\":1,\"contrast\":1,\"grain\":0.3,\"look\":\"Cinema\"}".utf8))
        precondition(oldRecipe.exposure == 0.5 && oldRecipe.cropZoom == 1, "Legacy edits lost")
        let archive = await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in
            library.exportArchive([saved]) { done.resume(returning: $0) }
        }
        guard let archive else { fatalError(library.error ?? "Archive export failed") }
        defer { try? FileManager.default.removeItem(at: archive) }
        let restored = RawPhotoLibrary(directory: base.appendingPathComponent("restored"))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in restored.importArchive(archive) { done.resume() } }
        guard let restoredShot = restored.shots.first else { fatalError(restored.error ?? "Archive import failed") }
        let restoredData = try Data(contentsOf: restored.original(restoredShot))
        precondition(restoredData == data && restoredShot.adjustments == changed && restoredShot.id != saved.id, "Archive did not preserve original and edits independently")
        let manifestURL = archive.appendingPathComponent("manifest.json")
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        var entries = manifest["shots"] as! [[String: Any]]
        var absent = entries[0]; absent["id"] = UUID().uuidString; entries.append(absent); manifest["shots"] = entries
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        let broken = RawPhotoLibrary(directory: base.appendingPathComponent("broken"))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in broken.importArchive(archive) { done.resume() } }
        precondition(broken.error != nil && broken.shots.isEmpty, "Incomplete archive import should fail atomically")
        let remaining = try FileManager.default.contentsOfDirectory(atPath: broken.root.path)
        precondition(remaining.isEmpty, "Failed import left partial files")
        let imports = RawPhotoLibrary(directory: base.appendingPathComponent("imports"))
        try imports.importImageData(data)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in imports.queue.async { DispatchQueue.main.async { done.resume() } } }
        precondition(imports.shots.first?.isRAW == true && imports.error == nil, imports.error ?? "DNG import failed")
        let jpegData = try RawDeveloper.jpeg(reduced)
        try imports.importImageData(jpegData)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in imports.queue.async { DispatchQueue.main.async { done.resume() } } }
        guard let jpegShot = imports.shots.first(where: { $0.format == "JPEG" }) else { fatalError(imports.error ?? "JPEG import missing") }
        let jpegOriginal = try Data(contentsOf: imports.original(jpegShot))
        precondition(!jpegShot.isRAW && jpegShot.fileExtension == "jpg" && jpegOriginal == jpegData, "Processed original mislabeled or changed")
        let mixedArchive = await withCheckedContinuation { (done: CheckedContinuation<URL?, Never>) in imports.exportArchive(imports.shots) { done.resume(returning: $0) } }
        guard let mixedArchive else { fatalError("Mixed archive missing") }
        defer { try? FileManager.default.removeItem(at: mixedArchive) }
        let mixed = RawPhotoLibrary(directory: base.appendingPathComponent("mixed"))
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in mixed.importArchive(mixedArchive) { done.resume() } }
        precondition(mixed.shots.count == 2 && mixed.error == nil, mixed.error ?? "Mixed originals did not round trip")
        print("RAW checks passed: archive round trip and rollback, legacy edits, accurate stored MP, crop and resize; DNG development, editing, stable grain, preview scale, durable metadata, unchanged original, DNG/JPEG/HEIC export")
    }
}

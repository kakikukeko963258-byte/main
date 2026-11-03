import Foundation
import UniformTypeIdentifiers
import ImageIO

enum RawPreferences {
    static var recipe: RawAdjustments {
        get { UserDefaults.standard.data(forKey: "raw-default-recipe").flatMap { try? JSONDecoder().decode(RawAdjustments.self, from: $0) } ?? RawAdjustments() }
        set { if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: "raw-default-recipe") } }
    }
}
extension UTType {
    static let rawCameraArchive = UTType(exportedAs: "com.kakikukeko.main.rawarchive", conformingTo: .package)
}
private struct RawArchiveManifest: Codable { var version = 1; var shots: [RawShot] }

extension RawPhotoLibrary {
    func importImage(_ url: URL) {
        busy = true
        queue.async {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                try self.importImageData(data)
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false } }
        }
    }
    func importImageData(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source),
              let uniform = UTType(type as String) else { throw RawCameraError.message("対応する画像を選択してください。") }
        let format: String
        if uniform.conforms(to: .rawImage) { format = "RAW" }
        else if uniform.conforms(to: .heic) || uniform.conforms(to: .heif) { format = "HEIC" }
        else if uniform.conforms(to: .jpeg) { format = "JPEG" }
        else if uniform.conforms(to: .png) { format = "PNG" }
        else if uniform.conforms(to: .tiff) { format = "TIFF" }
        else { throw RawCameraError.message("DNG・HEIC・JPEG・PNG・TIFFに対応しています。") }
        // Other camera RAW types must retain their native extension; this camera stores DNG originals.
        if format == "RAW" && !((type as String).lowercased().contains("dng")) && uniform.preferredFilenameExtension?.lowercased() != "dng" {
            throw RawCameraError.message("RAWの読み込みはDNG形式に対応しています。")
        }
        add(data: data, format: format) { self.busy = false; self.notice = "読み込みました" }
    }
    func exportArchive(_ selected: [RawShot], completion: @escaping (URL?) -> Void) {
        guard !selected.isEmpty else { return }
        busy = true
        queue.async {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Photos-\(UUID().uuidString).rawcamera", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for shot in selected {
                    try FileManager.default.copyItem(at: self.original(shot), to: folder.appendingPathComponent(shot.stem + "." + shot.fileExtension))
                    if FileManager.default.fileExists(atPath: self.thumbnail(shot).path) {
                        try FileManager.default.copyItem(at: self.thumbnail(shot), to: folder.appendingPathComponent(shot.stem + "-preview.jpg"))
                    }
                }
                try JSONEncoder().encode(RawArchiveManifest(shots: selected)).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
                DispatchQueue.main.async { self.busy = false; completion(folder) }
            } catch {
                try? FileManager.default.removeItem(at: folder)
                DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription; completion(nil) }
            }
        }
    }
    func importArchive(_ folder: URL, completion: (() -> Void)? = nil) {
        busy = true
        queue.async {
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            var created: [URL] = []
            do {
                let manifestURL = folder.appendingPathComponent("manifest.json")
                guard (try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < 32_000_000 else { throw RawCameraError.message("アーカイブの目録が大きすぎます。") }
                let archive = try JSONDecoder().decode(RawArchiveManifest.self, from: Data(contentsOf: manifestURL))
                guard archive.version == 1, archive.shots.count <= 10_000 else { throw RawCameraError.message("このアーカイブ形式は読み込めません。") }
                let base = folder.resolvingSymlinksInPath().standardizedFileURL.path + "/"
                var imported: [RawShot] = []
                for entry in archive.shots {
                    let source = folder.appendingPathComponent(entry.stem + "." + entry.fileExtension)
                    let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          source.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base) else { throw RawCameraError.message("アーカイブ内の画像を確認できません。") }
                    var copy = entry; copy.id = UUID()
                    let destination = self.original(copy)
                    try FileManager.default.copyItem(at: source, to: destination); created.append(destination)
                    let sidecar = self.root.appendingPathComponent(copy.stem + ".json")
                    try JSONEncoder().encode(copy).write(to: sidecar, options: .atomic); created.append(sidecar)
                    let preview = try RawDeveloper.image(destination, adjustments: copy.adjustments, maxSide: 1200)
                    let thumbnail = self.thumbnail(copy)
                    try RawDeveloper.jpeg(preview).write(to: thumbnail, options: .atomic); created.append(thumbnail)
                    imported.append(copy)
                }
                let result = imported
                DispatchQueue.main.async {
                    self.shotsForImport(result); self.busy = false; self.notice = "\(result.count)枚を読み込みました"; completion?()
                }
            } catch {
                created.forEach { try? FileManager.default.removeItem(at: $0) }
                DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription; completion?() }
            }
        }
    }
}

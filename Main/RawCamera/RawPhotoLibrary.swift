import Foundation
import Combine
import CoreImage
import Photos
import ImageIO
import UniformTypeIdentifiers

final class RawPhotoLibrary: ObservableObject {
    @Published private(set) var thumbnailRevision = 0
    @Published private(set) var shots: [RawShot] = []
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    let root: URL
    let queue = DispatchQueue(label: "main.raw.developer", qos: .userInitiated)
    init(directory: URL? = nil) {
        var override = directory
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-raw-fixture-ui-test") {
            override = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RawCameraUITest-" + UUID().uuidString)
        }
        #endif
        root = override ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RawCamera", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            shots = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .compactMap { try? JSONDecoder().decode(RawShot.self, from: Data(contentsOf: $0)) }
                .sorted { $0.date > $1.date }
        } catch { self.error = error.localizedDescription }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-raw-fixture-ui-test"),
           let path = ProcessInfo.processInfo.environment["RAW_CAMERA_TEST_FIXTURE"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            add(data: data, format: "RAW") {}
        }
        #endif
    }
    func original(_ shot: RawShot) -> URL { root.appendingPathComponent(shot.stem + "." + shot.fileExtension) }
    func thumbnail(_ shot: RawShot) -> URL { root.appendingPathComponent(shot.stem + ".jpg") }
    private func metadata(_ shot: RawShot) -> URL { root.appendingPathComponent(shot.stem + ".json") }
    func add(data: Data, format: String, metadata: RawCaptureMetadata? = nil, captured: Bool = true, completion: @escaping () -> Void) {
        var defaults = RawPreferences.recipe
        if captured { defaults.cropAspect = UserDefaults.standard.string(forKey: "raw-capture-aspect") ?? "Original" }
        queue.async {
            let ext = format == "HEIC" ? "heic" : format == "JPEG" ? "jpg" : format == "PNG" ? "png" : format == "TIFF" ? "tiff" : "dng"
            var details = metadata
            var date = Date()
            if let source = CGImageSourceCreateWithData(data as CFData, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                var width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.intValue ?? 0
                var height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.intValue ?? 0
                if ext == "dng", let raw = CIRAWFilter(imageData: data, identifierHint: "com.adobe.raw-image"), raw.nativeSize.width > 0 {
                    width = Int(raw.nativeSize.width); height = Int(raw.nativeSize.height)
                    if details == nil { details = RawCaptureMetadata(width: width, height: height) }
                    details?.temperature = Double(raw.neutralTemperature)
                }
                let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
                if let timestamp = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                    if let offset = exif["OffsetTimeOriginal"] as? String { formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXX"; date = formatter.date(from: timestamp + offset) ?? date }
                    else { formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"; date = formatter.date(from: timestamp) ?? date }
                }
                if details == nil { details = RawCaptureMetadata(width: width, height: height) }
                if details?.iso == nil { details?.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue }
                if details?.seconds == nil { details?.seconds = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue }
                if details?.aperture == nil { details?.aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue }
                if details?.lens == nil { details?.lens = exif[kCGImagePropertyExifLensModel as String] as? String }
                if width > 0 && height > 0 {
                    if details == nil { details = RawCaptureMetadata(width: width, height: height) }
                    else { details?.width = width; details?.height = height }
                }
            }
            let shot = RawShot(id: UUID(), date: date, format: format, adjustments: defaults, originalExtension: ext, capture: details)
            do {
                try data.write(to: self.original(shot), options: .atomic)
                try JSONEncoder().encode(shot).write(to: self.metadata(shot), options: .atomic)
                // The DNG and metadata are committed before rendering. Failed development cannot lose the original.
                DispatchQueue.main.async { self.shots.insert(shot, at: 0) }
                do {
                    let image = try RawDeveloper.image(self.original(shot), adjustments: shot.adjustments, maxSide: 1200)
                    try RawDeveloper.jpeg(image).write(to: self.thumbnail(shot), options: .atomic)
                    DispatchQueue.main.async { self.thumbnailRevision += 1 }
                } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
                DispatchQueue.main.async {
                    if captured && UserDefaults.standard.bool(forKey: "raw-auto-export") { self.saveToPhotos(shot, raw: false) }
                    completion()
                }
            } catch { DispatchQueue.main.async { self.error = "RAW保存に失敗しました: \(error.localizedDescription)"; completion() } }
        }
    }
    func save(_ shot: RawShot, adjustments: RawAdjustments) {
        var updated = shot; updated.adjustments = adjustments
        busy = true
        queue.async {
            do {
                try JSONEncoder().encode(updated).write(to: self.metadata(updated), options: .atomic)
                let committed = updated
                DispatchQueue.main.async {
                    if let i = self.shots.firstIndex(where: { $0.id == committed.id }) { self.shots[i] = committed }
                }
                let image = try RawDeveloper.image(self.original(updated), adjustments: adjustments, maxSide: 1200)
                try RawDeveloper.jpeg(image).write(to: self.thumbnail(updated), options: .atomic)
                DispatchQueue.main.async { self.thumbnailRevision += 1; self.busy = false }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false } }
        }
    }
    func export(_ shot: RawShot, kind: String, maxSide: Int? = nil, completion: @escaping (URL?) -> Void) {
        busy = true
        let exportSide = maxSide ?? UserDefaults.standard.integer(forKey: "raw-export-size")
        queue.async {
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RawExports", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                if kind == "DNG" && !shot.isRAW { throw RawCameraError.message("この写真はHEIC/JPEG原本です。RAWへの変換はできません。原本を書き出してください。") }
                let suffix = kind == "Original" ? shot.fileExtension : kind == "DNG" ? "dng" : kind == "HEIC" ? "heic" : "jpg"
                let url = dir.appendingPathComponent("\(shot.stem)-\(UUID().uuidString).\(suffix)")
                if kind == "DNG" || kind == "Original" { try FileManager.default.copyItem(at: self.original(shot), to: url) }
                else {
                    let image = try RawDeveloper.image(self.original(shot), adjustments: shot.adjustments, maxSide: exportSide > 0 ? CGFloat(exportSide) : nil)
                    var properties: [String: Any] = [:]
                    if let source = CGImageSourceCreateWithURL(self.original(shot) as CFURL, nil), let original = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] {
                        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary] {
                            if let value = original[key as String] { properties[key as String] = value }
                        }
                        if UserDefaults.standard.bool(forKey: "raw-export-location"), let gps = original[kCGImagePropertyGPSDictionary as String] { properties[kCGImagePropertyGPSDictionary as String] = gps }
                    }
                    try RawDeveloper.encoded(image, kind: kind, properties: properties).write(to: url, options: .atomic)
                }
                DispatchQueue.main.async { self.busy = false; completion(url) }
            } catch { DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription; completion(nil) } }
        }
    }
    func saveToPhotos(_ shot: RawShot, raw: Bool, kind: String? = nil) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.error = "写真への追加を設定アプリで許可してください。DNGはアプリ内に保存されています。" }; return
            }
            DispatchQueue.main.async {
                self.export(shot, kind: raw ? "Original" : (kind ?? UserDefaults.standard.string(forKey: "raw-export-format") ?? "JPEG")) { url in
                    guard let url else { return }
                    PHPhotoLibrary.shared().performChanges {
                        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                    } completionHandler: { success, error in
                        DispatchQueue.main.async {
                            if success { self.notice = "写真に保存しました" }
                            else { self.error = error?.localizedDescription ?? "写真への保存に失敗しました。" }
                        }
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
        }
    }
    func shotsForImport(_ imported: [RawShot]) {
        shots = (shots + imported).sorted { $0.date > $1.date }; thumbnailRevision += 1
    }
    func delete(_ shot: RawShot) {
        busy = true
        queue.async {
            do {
                // Remove the source first: a failure leaves the gallery entry available for retry.
                try FileManager.default.removeItem(at: self.original(shot))
                try? FileManager.default.removeItem(at: self.thumbnail(shot))
                try FileManager.default.removeItem(at: self.metadata(shot))
                DispatchQueue.main.async { self.shots.removeAll { $0.id == shot.id }; self.busy = false }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false } }
        }
    }
}

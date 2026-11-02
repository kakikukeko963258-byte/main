import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos
import UniformTypeIdentifiers

struct RawAdjustments: Codable, Equatable {
    var exposure: Double = 0
    var warmth: Double = 0
    var saturation: Double = 1
    var contrast: Double = 1
    var grain: Double = 0.12
    var look: String = "Cinema"
}

struct RawShot: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var format: String
    var adjustments: RawAdjustments
    var stem: String { id.uuidString }
}

enum RawCameraError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum RawDeveloper {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static func image(_ url: URL, adjustments a: RawAdjustments, maxSide: CGFloat? = nil) throws -> CIImage {
        guard let raw = CIRAWFilter(imageURL: url) else {
            throw RawCameraError.message("このRAWを現像できません。DNG原本は保持されています。")
        }
        raw.exposure = Float(a.exposure)
        // Avoid the manufacturer's baseline tone boost before our own rendering.
        raw.baselineExposure = 0
        raw.boostAmount = 0
        if let maxSide { raw.scaleFactor = Float(min(1, maxSide / max(raw.nativeSize.width, raw.nativeSize.height))) }
        guard var image = raw.outputImage else { throw RawCameraError.message("RAWの読み込みに失敗しました。") }
        let extent = image.extent
        image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        if a.look != "Neutral" {
            let curve = CIFilter.toneCurve()
            curve.inputImage = image
            curve.point0 = CGPoint(x: 0, y: 0.025)
            curve.point1 = CGPoint(x: 0.22, y: 0.18)
            curve.point2 = CGPoint(x: 0.5, y: 0.51)
            curve.point3 = CGPoint(x: 0.78, y: 0.83)
            curve.point4 = CGPoint(x: 1, y: 0.97)
            image = curve.outputImage ?? image
            if a.look == "Cinema" {
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1.025, y: -0.015, z: -0.01, w: 0),
                    "inputGVector": CIVector(x: 0.015, y: 0.985, z: 0, w: 0),
                    "inputBVector": CIVector(x: -0.015, y: 0.025, z: 0.99, w: 0)])
            }
        }
        image = image.applyingFilter("CITemperatureAndTint", parameters: [
            "inputNeutral": CIVector(x: 6500, y: 0),
            "inputTargetNeutral": CIVector(x: 6500 + a.warmth * 1800, y: 0)])
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: a.look == "Mono" ? 0 : a.saturation * (a.look == "Cinema" ? 0.88 : 1),
            kCIInputContrastKey: a.contrast])
        if a.grain > 0 {
            // A repeatable texture keeps the grain stable while editing and exporting.
            let noise = CIImage(image: grainTile)!
                .applyingFilter("CIAffineTile", parameters: [kCIInputTransformKey: NSValue(cgAffineTransform: .identity)])
                .cropped(to: image.extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a.grain * 0.3)])
            image = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        }
        return image.cropped(to: image.extent)
    }
    private static let grainTile: UIImage = {
        var state: UInt32 = 81273
        var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
        for p in stride(from: 0, to: bytes.count, by: 4) {
            state = 1664525 &* state &+ 1013904223
            let value = UInt8(state >> 24)
            bytes[p] = value; bytes[p + 1] = value; bytes[p + 2] = value; bytes[p + 3] = 255
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let cg = CGImage(width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32,
                         bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(),
                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: cg)
    }()
    static func jpeg(_ image: CIImage) throws -> Data {
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]) else {
            throw RawCameraError.message("JPEGの作成に失敗しました。")
        }
        return data
    }
}

final class RawPhotoLibrary: ObservableObject {
    @Published private(set) var shots: [RawShot] = []
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    let root: URL
    let queue = DispatchQueue(label: "main.raw.developer", qos: .userInitiated)
    init() {
        root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RawCamera", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            shots = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .compactMap { try? JSONDecoder().decode(RawShot.self, from: Data(contentsOf: $0)) }
                .sorted { $0.date > $1.date }
        } catch { self.error = error.localizedDescription }
    }
    func original(_ shot: RawShot) -> URL { root.appendingPathComponent(shot.stem + ".dng") }
    func thumbnail(_ shot: RawShot) -> URL { root.appendingPathComponent(shot.stem + ".jpg") }
    private func metadata(_ shot: RawShot) -> URL { root.appendingPathComponent(shot.stem + ".json") }
    func add(data: Data, format: String, completion: @escaping () -> Void) {
        queue.async {
            let shot = RawShot(id: UUID(), date: Date(), format: format, adjustments: RawAdjustments())
            do {
                try data.write(to: self.original(shot), options: .atomic)
                try JSONEncoder().encode(shot).write(to: self.metadata(shot), options: .atomic)
                // The DNG and metadata are committed before rendering. Failed development cannot lose the original.
                DispatchQueue.main.async { self.shots.insert(shot, at: 0) }
                do {
                    let image = try RawDeveloper.image(self.original(shot), adjustments: shot.adjustments, maxSide: 1200)
                    try RawDeveloper.jpeg(image).write(to: self.thumbnail(shot), options: .atomic)
                    DispatchQueue.main.async { self.objectWillChange.send() }
                } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
                DispatchQueue.main.async {
                    if UserDefaults.standard.bool(forKey: "raw-auto-export") { self.saveToPhotos(shot, raw: false) }
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
                DispatchQueue.main.async { self.objectWillChange.send(); self.busy = false }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.busy = false } }
        }
    }
    func export(_ shot: RawShot, kind: String, completion: @escaping (URL?) -> Void) {
        busy = true
        queue.async {
            do {
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("RawExports", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let suffix = kind == "DNG" ? "dng" : kind == "HEIC" ? "heic" : "jpg"
                let url = dir.appendingPathComponent("\(shot.stem)-\(UUID().uuidString).\(suffix)")
                if kind == "DNG" { try FileManager.default.copyItem(at: self.original(shot), to: url) }
                else {
                    let image = try RawDeveloper.image(self.original(shot), adjustments: shot.adjustments)
                    if kind == "HEIC" {
                        try RawDeveloper.context.writeHEIFRepresentation(of: image, to: url, format: .RGBA8,
                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:])
                    } else { try RawDeveloper.jpeg(image).write(to: url, options: .atomic) }
                }
                DispatchQueue.main.async { self.busy = false; completion(url) }
            } catch { DispatchQueue.main.async { self.busy = false; self.error = error.localizedDescription; completion(nil) } }
        }
    }
    func saveToPhotos(_ shot: RawShot, raw: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { self.error = "写真への追加を設定アプリで許可してください。DNGはアプリ内に保存されています。" }; return
            }
            DispatchQueue.main.async {
                self.export(shot, kind: raw ? "DNG" : "JPEG") { url in
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

import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

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
        guard !image.extent.isEmpty, !image.extent.isInfinite else { throw RawCameraError.message("このRAWの現像データを読み込めません。DNG原本は保持されています。") }
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
            let tile = CIFilter.affineTile()
            tile.inputImage = CIImage(cgImage: grainTile)
            tile.transform = .identity
            let noise = tile.outputImage!
                .cropped(to: image.extent)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a.grain * 0.3)])
            image = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        }
        return image.cropped(to: image.extent)
    }
    private static let grainTile: CGImage = {
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
        return cg
    }()
    static func jpeg(_ image: CIImage) throws -> Data {
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]) else {
            throw RawCameraError.message("JPEGの作成に失敗しました。")
        }
        return data
    }
}


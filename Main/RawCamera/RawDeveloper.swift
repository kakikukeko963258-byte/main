import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO

struct RawAdjustments: Codable, Equatable {
    var exposure = 0.0, warmth = 0.0, tint = 0.0, saturation = 1.0, contrast = 1.0
    var highlights = 0.0, shadows = 0.0, blackPoint = 0.0
    var grain = 1.25, grainSize = 1.0, halation = 0.35, halationRadius = 1.0
    var forcePixelGrain = false
    var look = "Cinema", cropAspect = "Original"
    var rotation = 0
    var flipH = false, flipV = false
    var cropZoom = 1.0, cropX = 0.5, cropY = 0.5
    init() {}
    enum CodingKeys: String, CodingKey {
        case exposure, warmth, tint, saturation, contrast, highlights, shadows, blackPoint
        case grain, grainSize, halation, halationRadius, forcePixelGrain, look, cropAspect
        case rotation, flipH, flipV, cropZoom, cropX, cropY
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func n(_ k: CodingKeys, _ fallback: Double, _ range: ClosedRange<Double>) throws -> Double {
            let value = try c.decodeIfPresent(Double.self, forKey: k) ?? fallback
            return value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        exposure = try n(.exposure, 0, -4...4); warmth = try n(.warmth, 0, -1...1)
        tint = try n(.tint, 0, -100...100); saturation = try n(.saturation, 1, 0...2)
        contrast = try n(.contrast, 1, 0.5...1.5); highlights = try n(.highlights, 0, 0...1)
        shadows = try n(.shadows, 0, -1...1); blackPoint = try n(.blackPoint, 0, -0.1...0.1)
        grain = try n(.grain, 0.12, 0...5); grainSize = try n(.grainSize, 1, 0.25...4)
        halation = try n(.halation, 0.35, 0...2); halationRadius = try n(.halationRadius, 1, 0.25...4)
        forcePixelGrain = try c.decodeIfPresent(Bool.self, forKey: .forcePixelGrain) ?? false
        look = try c.decodeIfPresent(String.self, forKey: .look) ?? "Cinema"
        cropAspect = try c.decodeIfPresent(String.self, forKey: .cropAspect) ?? "Original"
        rotation = ((try c.decodeIfPresent(Int.self, forKey: .rotation) ?? 0) % 4 + 4) % 4
        flipH = try c.decodeIfPresent(Bool.self, forKey: .flipH) ?? false
        flipV = try c.decodeIfPresent(Bool.self, forKey: .flipV) ?? false
        cropZoom = try n(.cropZoom, 1, 1...4); cropX = try n(.cropX, 0.5, 0...1); cropY = try n(.cropY, 0.5, 0...1)
    }
}

struct RawCaptureMetadata: Codable, Equatable {
    var width: Int, height: Int
    var iso: Double?, seconds: Double?, aperture: Double?, lens: String?
    var temperature: Double?
    var megapixels: Double { Double(width) * Double(height) / 1_000_000 }
}
struct RawShot: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var format: String
    var adjustments: RawAdjustments
    var originalExtension: String?
    var capture: RawCaptureMetadata?
    var stem: String { id.uuidString }
    var fileExtension: String { ["dng", "heic", "jpg", "tiff", "png"].contains(originalExtension ?? "dng") ? (originalExtension ?? "dng") : "dng" }
    var isRAW: Bool { fileExtension == "dng" }
}

enum RawCameraError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum RawDeveloper {
    static let context = CIContext(options: [.cacheIntermediates: false])
    static func image(_ url: URL, adjustments a: RawAdjustments, maxSide: CGFloat? = nil) throws -> CIImage {
        let decodeSide = maxSide.map { $0 * CGFloat(a.cropZoom) * (a.cropAspect == "Original" ? 1 : 2) }
        let nativeLongSide: CGFloat
        var image: CIImage
        if url.pathExtension.lowercased() == "dng" {
        guard let raw = CIRAWFilter(imageURL: url) else {
            throw RawCameraError.message("このRAWを現像できません。DNG原本は保持されています。")
        }
        raw.exposure = Float(a.exposure)
        // Avoid the manufacturer's baseline tone boost before our own rendering.
        raw.baselineExposure = 0
        raw.boostAmount = 0
        nativeLongSide = max(raw.nativeSize.width, raw.nativeSize.height)
        if let decodeSide { raw.scaleFactor = Float(min(1, decodeSide / max(raw.nativeSize.width, raw.nativeSize.height))) }
        guard let decoded = raw.outputImage else { throw RawCameraError.message("RAWの読み込みに失敗しました。") }
        image = decoded
        } else {
            guard let decoded = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { throw RawCameraError.message("画像を読み込めません。") }
            nativeLongSide = max(decoded.extent.width, decoded.extent.height)
            image = decoded
            if let decodeSide, nativeLongSide > decodeSide { image = image.transformed(by: CGAffineTransform(scaleX: decodeSide / nativeLongSide, y: decodeSide / nativeLongSide)) }
            image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: a.exposure])
        }
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
            "inputTargetNeutral": CIVector(x: 6500 + a.warmth * 1800, y: a.tint)])
        image = image.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: a.look == "Mono" ? 0 : a.saturation * (a.look == "Cinema" ? 0.88 : 1),
            kCIInputContrastKey: a.contrast])
        image = image.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": 1 - a.highlights * 0.7, "inputShadowAmount": a.shadows])
        if a.blackPoint != 0 {
            image = image.applyingFilter("CIColorMatrix", parameters: ["inputBiasVector": CIVector(x: a.blackPoint, y: a.blackPoint, z: a.blackPoint, w: 0)])
        }
        if a.halation > 0 && a.look != "Neutral" {
            let bounds = image.extent
            let mono = CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0)
            let mask = image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": mono, "inputGVector": mono, "inputBVector": mono])
                .applyingFilter("CIColorPolynomial", parameters: ["inputRedCoefficients": CIVector(x: -5.2, y: 7, z: 0, w: 0), "inputGreenCoefficients": CIVector(x: -5.2, y: 7, z: 0, w: 0), "inputBlueCoefficients": CIVector(x: -5.2, y: 7, z: 0, w: 0)])
                .applyingFilter("CIColorClamp")
            let glow = CIImage(color: CIColor(red: 1, green: 0.25, blue: 0.06, alpha: min(1, a.halation * 0.3))).cropped(to: bounds)
                .applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: bounds), kCIInputMaskImageKey: mask])
                .clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(bounds.width, bounds.height) * 0.003 * a.halationRadius]).cropped(to: bounds)
            image = glow.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: bounds)
        }
        if a.grain > 0 {
            let side = max(image.extent.width, image.extent.height)
            let size = a.grainSize * (a.forcePixelGrain ? side / max(1, nativeLongSide) : side / 2400)
            guard let kernel = grainKernel, let output = kernel.apply(extent: image.extent, arguments: [image, a.grain * 0.022, max(0.1, size)]) else {
                throw RawCameraError.message("粒子の現像に失敗しました。原本は保持されています。")
            }
            image = output
        }
        if a.rotation != 0 { image = image.oriented(forExifOrientation: [1, 6, 3, 8][a.rotation % 4]) }
        if a.flipH { image = image.oriented(forExifOrientation: 2) }
        if a.flipV { image = image.oriented(forExifOrientation: 4) }
        let bounds = image.extent
        let ratios: [String: CGFloat] = ["1:1": 1, "4:3": 4.0/3, "3:2": 1.5, "16:9": 16.0/9, "3:4": 0.75, "9:16": 9.0/16]
        let ratio = ratios[a.cropAspect] ?? bounds.width / bounds.height
        var width = bounds.width, height = width / ratio
        if height > bounds.height { height = bounds.height; width = height * ratio }
        width /= a.cropZoom; height /= a.cropZoom
        let crop = CGRect(x: bounds.minX + (bounds.width - width) * a.cropX, y: bounds.minY + (bounds.height - height) * a.cropY, width: width, height: height).integral.intersection(bounds)
        image = image.cropped(to: crop)
        image = image.transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let side = max(image.extent.width, image.extent.height)
        if let maxSide, side > maxSide { image = image.transformed(by: CGAffineTransform(scaleX: maxSide / side, y: maxSide / side)) }
        return image
    }
    private static let grainKernel = CIColorKernel(source: """
        kernel vec4 stableGrain(__sample source, float amount, float cellSize) {
            vec2 p = floor(destCoord() / cellSize);
            float a = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
            float b = fract(sin(dot(p + vec2(13.0, 71.0), vec2(269.5, 183.3))) * 23421.631);
            float c = fract(sin(dot(p + vec2(53.0, 19.0), vec2(419.2, 371.9))) * 31251.918);
            vec4 color = unpremultiply(source);
            float luminance = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
            float density = 0.35 + 0.65 * sqrt(clamp(luminance, 0.0, 1.0));
            color.rgb = clamp(color.rgb + (a+b+c-1.5) * amount * density, 0.0, 1.0);
            return premultiply(color);
        }
        """)
    static func encoded(_ image: CIImage, kind: String, properties: [String: Any]) throws -> Data {
        let data = NSMutableData()
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
              let destination = CGImageDestinationCreateWithData(data, (kind == "HEIC" ? "public.heic" : "public.jpeg") as CFString, 1, nil) else {
            throw RawCameraError.message("画像の書き出しを開始できません。")
        }
        var metadata = properties
        metadata[kCGImageDestinationLossyCompressionQuality as String] = 0.94
        metadata[kCGImagePropertyOrientation as String] = 1
        metadata[kCGImagePropertyPixelWidth as String] = cg.width
        metadata[kCGImagePropertyPixelHeight as String] = cg.height
        var exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        exif[kCGImagePropertyExifPixelXDimension as String] = cg.width
        exif[kCGImagePropertyExifPixelYDimension as String] = cg.height
        metadata[kCGImagePropertyExifDictionary as String] = exif
        CGImageDestinationAddImage(destination, cg, metadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw RawCameraError.message("画像の書き出しに失敗しました。") }
        return data as Data
    }
    static func jpeg(_ image: CIImage) throws -> Data {
        guard let data = context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                     options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.94]) else {
            throw RawCameraError.message("JPEGの作成に失敗しました。")
        }
        return data
    }
}


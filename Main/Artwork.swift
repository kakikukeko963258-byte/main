import SwiftUI
import UIKit
import ImageIO

// Expensive artwork is rasterized once, then Core Animation moves the cached images.
// Liquid Glass remains on the open folder and controls, rather than 32 nested live lenses.
enum IconArtwork {
    private static let cache = NSCache<NSString, UIImage>()
    static func image(_ slot: Int) -> UIImage {
        let key = "slot-\(slot)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let side: CGFloat = 256
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { renderer in
            let context = renderer.cgContext
            let bounds = CGRect(x: 1, y: 1, width: side - 2, height: side - 2)
            let path = IconContour().path(in: bounds).cgPath
            let hues: [CGFloat] = [0.58, 0.48, 0.35, 0.08, 0.66, 0.97, 0.12, 0.56]
            let hue = hues[(slot - 1) % hues.count]
            context.saveGState()
            context.addPath(path); context.clip()
            let colors = [UIColor(hue: hue, saturation: 0.60, brightness: 0.77, alpha: 1).cgColor,
                          UIColor(hue: hue, saturation: 0.85, brightness: 0.43, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            context.restoreGState()
            context.addPath(path); context.setStrokeColor(UIColor.white.withAlphaComponent(0.30).cgColor)
            context.setLineWidth(1.3); context.strokePath()
            let font = UIFont.systemFont(ofSize: side * 0.44, weight: .medium)
            let rounded = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded) ?? font.fontDescriptor, size: font.pointSize)
            let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: UIColor.white]
            let text = "\(slot)" as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - textSize.width) / 2, y: (side - textSize.height) / 2), withAttributes: attributes)
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

enum WallpaperArtwork {
    private static let cache = NSCache<NSString, UIImage>()
    static func downsample(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2800,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
    static func image(size: CGSize) -> UIImage {
        let key = "\(Int(size.width))-\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let result = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let context = renderer.cgContext
            let colors = [UIColor(red: 0.02, green: 0.30, blue: 0.49, alpha: 1).cgColor,
                          UIColor(red: 0.06, green: 0.47, blue: 0.71, alpha: 1).cgColor,
                          UIColor(red: 0.10, green: 0.16, blue: 0.17, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            func glow(_ color: UIColor, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
                context.saveGState()
                context.translateBy(x: size.width * x, y: size.height * y)
                context.scaleBy(x: size.width * width, y: size.height * height)
                let colors = [color.cgColor, color.withAlphaComponent(0.75).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 1]) {
                    context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
                }
                context.restoreGState()
            }
            glow(UIColor(red: 0.63, green: 0.57, blue: 0.41, alpha: 1), x: 0.47, y: 0.57, width: 0.48, height: 0.40)
            glow(UIColor(red: 0.80, green: 0.64, blue: 0.35, alpha: 1), x: 0.73, y: 0.77, width: 0.34, height: 0.39)
            glow(UIColor(red: 0.12, green: 0.16, blue: 0.09, alpha: 1), x: 0.30, y: 0.91, width: 0.65, height: 0.38)
        }
        cache.setObject(result, forKey: key)
        return result
    }
}

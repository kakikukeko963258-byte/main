import UIKit

// Calendar launch in the supplied 60 fps recording, measured on a 390 x 844
// canvas. These are the straight-edge intersections, before rounding corners.
// Keeping the four edges (rather than a bounding-box zoom) retains the brief
// downward movement and the narrower top of the opening window.
struct LaunchMorph {
    struct Sample {
        let time: CGFloat
        let leftTop: CGFloat
        let rightTop: CGFloat
        let leftBottom: CGFloat
        let rightBottom: CGFloat
        let top: CGFloat
        let bottom: CGFloat
        var width: CGFloat { (rightTop - leftTop + rightBottom - leftBottom) / 2 }
        var height: CGFloat { bottom - top }
    }
    private static let samples: [Sample] = [
        .init(time: 0, leftTop: 28, rightTop: 92, leftBottom: 28, rightBottom: 92, top: 67, bottom: 131),
        .init(time: 1/60, leftTop: 26, rightTop: 98, leftBottom: 26, rightBottom: 105, top: 81, bottom: 164),
        .init(time: 2/60, leftTop: 22, rightTop: 119, leftBottom: 20, rightBottom: 143, top: 104, bottom: 245),
        .init(time: 3/60, leftTop: 16, rightTop: 147, leftBottom: 14, rightBottom: 188, top: 121, bottom: 346),
        .init(time: 4/60, leftTop: 13, rightTop: 181, leftBottom: 9, rightBottom: 233, top: 126, bottom: 443),
        .init(time: 5/60, leftTop: 11, rightTop: 219, leftBottom: 5, rightBottom: 271, top: 118, bottom: 540),
        .init(time: 6/60, leftTop: 9, rightTop: 252, leftBottom: 3, rightBottom: 302, top: 105, bottom: 617),
        .init(time: 7/60, leftTop: 7, rightTop: 281, leftBottom: 2, rightBottom: 328, top: 88, bottom: 679),
        .init(time: 8/60, leftTop: 5, rightTop: 306, leftBottom: 1, rightBottom: 346, top: 72, bottom: 726),
        .init(time: 9/60, leftTop: 4, rightTop: 326, leftBottom: 0, rightBottom: 360, top: 58, bottom: 760),
        .init(time: 10/60, leftTop: 3, rightTop: 340, leftBottom: 0, rightBottom: 369, top: 45, bottom: 785),
        .init(time: 11/60, leftTop: 3, rightTop: 354, leftBottom: 0, rightBottom: 376, top: 35, bottom: 803),
        .init(time: 12/60, leftTop: 3, rightTop: 362, leftBottom: 0, rightBottom: 381, top: 26, bottom: 816),
        .init(time: 13/60, leftTop: 3, rightTop: 369, leftBottom: 0, rightBottom: 384, top: 20, bottom: 825),
        .init(time: 14/60, leftTop: 3, rightTop: 374, leftBottom: 0, rightBottom: 386, top: 15, bottom: 831),
        .init(time: 16/60, leftTop: 2, rightTop: 381, leftBottom: 0, rightBottom: 389, top: 8, bottom: 838),
        .init(time: 20/60, leftTop: 1, rightTop: 387, leftBottom: 0, rightBottom: 390, top: 2, bottom: 843),
        .init(time: 26/60, leftTop: 0, rightTop: 390, leftBottom: 0, rightBottom: 390, top: 0, bottom: 844),
        .init(time: 0.5, leftTop: 0, rightTop: 390, leftBottom: 0, rightBottom: 390, top: 0, bottom: 844)
    ]
    static let duration: CFTimeInterval = 0.5

    private static func sample(_ progress: CGFloat) -> Sample {
        let time = min(1, max(0, progress)) * CGFloat(duration)
        let next = samples.firstIndex(where: { $0.time >= time }) ?? samples.count - 1
        guard next > 0 else { return samples[0] }
        let a = samples[next - 1], b = samples[next]
        let t = (time - a.time) / (b.time - a.time)
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        return Sample(time: time, leftTop: mix(a.leftTop, b.leftTop), rightTop: mix(a.rightTop, b.rightTop),
                      leftBottom: mix(a.leftBottom, b.leftBottom), rightBottom: mix(a.rightBottom, b.rightBottom),
                      top: mix(a.top, b.top), bottom: mix(a.bottom, b.bottom))
    }

    // Interactive swipes express window size, not elapsed launch time.
    static func progress(forExpansion expansion: CGFloat) -> CGFloat {
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            if (sample(mid).height - 64) / 780 < expansion { lo = mid } else { hi = mid }
        }
        return expansion <= 0 ? 0 : (expansion >= 1 ? 1 : (lo + hi) / 2)
    }

    let transform: CATransform3D
    let size: CGSize
    let expansion: CGFloat

    init(progress: CGFloat, source: CGRect, screen: CGSize) {
        let s = Self.sample(progress)
        let widthProgress = (s.width - 64) / 326
        expansion = (s.height - 64) / 780
        let w = source.width + (screen.width - source.width) * widthProgress
        let h = source.height + (screen.height - source.height) * expansion
        size = CGSize(width: w, height: h)
        let cxProgress = ((s.leftTop + s.rightTop + s.leftBottom + s.rightBottom) / 4 - 60) / 135
        let cyProgress = ((s.top + s.bottom) / 2 - 99) / 323
        let cx = source.midX + (screen.width / 2 - source.midX) * cxProgress
        let cy = source.midY + (screen.height / 2 - source.midY) * cyProgress
        // Reflect the perspective for icons in the lower/right part of Home.
        let verticalOffset = max(-1.3, min(1.3, (screen.height / 2 - source.midY) / (screen.height * 323 / 844)))
        let taper = (s.rightBottom - s.leftBottom - s.rightTop + s.leftTop) / s.width * verticalOffset
        let skew = ((s.leftBottom + s.rightBottom - s.leftTop - s.rightTop) / 2) / 135 * (screen.width / 2 - source.midX)
        let wt = w * (1 - taper / 2), wb = w * (1 + taper / 2)
        let topLeft = CGPoint(x: cx - skew / 2 - wt / 2, y: cy - h / 2)
        let bottomLeft = CGPoint(x: cx + skew / 2 - wb / 2, y: cy + h / 2)
        // Project the cached full-screen surface onto a trapezoid. Its artwork
        // and page share this homography, so the icon visibly stretches with it.
        let perspective = wt / wb - 1
        var m = CATransform3DIdentity
        m.m11 = wt / screen.width
        m.m21 = (bottomLeft.x * (1 + perspective) - topLeft.x) / screen.height
        m.m41 = topLeft.x
        m.m22 = (bottomLeft.y * (1 + perspective) - topLeft.y) / screen.height
        m.m42 = topLeft.y
        m.m24 = perspective / screen.height
        transform = m
    }
}

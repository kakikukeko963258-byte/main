import Foundation

/// Full-rate recent data and a bounded long-term record. Never invent samples
/// between reads. Charts preserve per-metric extrema and missing-data boundaries.
enum ChargingHistory {
    static func chart(_ samples: [ChargeSample], limit: Int = 360) -> [ChargeSample] {
        guard samples.count > limit else { return samples }
        let width = max(1, Int(ceil(Double(samples.count) / Double(max(1, limit / 10)))))
        var indices = Set<Int>()
        for start in stride(from: 0, to: samples.count, by: width) {
            let end = min(samples.count, start + width)
            indices.insert(start); indices.insert(end - 1)
            for metric in 0..<3 {
                func value(_ index: Int) -> Double? {
                    switch metric {
                    case 0: return samples[index].watts
                    case 1: return samples[index].temperature
                    default: return samples[index].percent.map(Double.init)
                    }
                }
                let valid = (start..<end).filter { value($0) != nil }
                if let low = valid.min(by: { value($0)! < value($1)! }) { indices.insert(low) }
                if let high = valid.max(by: { value($0)! < value($1)! }) { indices.insert(high) }
            }
        }
        for i in 1..<samples.count {
            let a = samples[i - 1], b = samples[i]
            if a.session != b.session || b.date.timeIntervalSince(a.date) > 30 ||
                (a.watts == nil) != (b.watts == nil) ||
                (a.temperature == nil) != (b.temperature == nil) ||
                (a.percent == nil) != (b.percent == nil) {
                indices.insert(i - 1); indices.insert(i)
            }
        }
        return indices.sorted().map { samples[$0] }
    }
}

actor ChargingDiskStore {
    private let url: URL
    init(url: URL) { self.url = url }
    func save(_ samples: [ChargeSample]) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(samples).write(to: url, options: .atomic)
        } catch { /* Monitoring continues if device protection prevents a disk write. */ }
    }
}

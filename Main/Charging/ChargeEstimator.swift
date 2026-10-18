import Foundation

struct ChargeSample: Codable, Identifiable {
    var id: Date { date }
    var date: Date
    var session: UUID
    var percent: Int?
    var watts: Double?
    var temperature: Double?
    var charging: Bool
}

/// No assumed battery capacity or rated adapter power. Rates are percent/second.
enum ChargeEstimator {
    static func taper(_ percent: Double) -> Double {
        if percent < 70 { return 1 }
        if percent < 80 { return 0.8 }
        if percent < 90 { return 0.5 }
        if percent < 95 { return 0.3 }
        return 0.16
    }
    static func eta(target: Int, now: Date, percent: Int, session: UUID,
                    samples: [ChargeSample]) -> Date? {
        guard percent < target else { return nil }
        let recent = samples.filter { $0.session == session && $0.charging &&
            now.timeIntervalSince($0.date) <= 1200 && $0.percent != nil }
        guard let last = recent.last, now.timeIntervalSince(last.date) < 30 else { return nil }
        // Split at every suspension gap, disconnect, or falling percentage.
        var segment: [ChargeSample] = []
        for sample in recent {
            if let prior = segment.last,
               sample.date.timeIntervalSince(prior.date) > 30 || sample.percent! < prior.percent! {
                segment.removeAll()
            }
            segment.append(sample)
        }
        guard let first = segment.first, let end = segment.last,
              end.date.timeIntervalSince(first.date) >= 180,
              end.percent! - first.percent! >= 2 else { return nil }
        // No progress for ten minutes may be a charging limit / thermal hold.
        if let changed = segment.last(where: { $0.percent! < percent }),
           now.timeIntervalSince(changed.date) > 600 { return nil }
        let rate = Double(end.percent! - first.percent!) / end.date.timeIntervalSince(first.date)
        let baseRate = rate / taper(Double(first.percent! + end.percent!) / 2)
        guard baseRate > 0, baseRate.isFinite else { return nil }
        var seconds = 0.0
        // Historical data learns the taper in each 10% band. A conservative
        // fallback curve covers bands not observed yet; all results are estimates.
        var bandRates: [Int: [Double]] = [:]
        var anchor: ChargeSample?
        var previous: ChargeSample?
        for sample in samples {
            defer { previous = sample }
            guard sample.charging, let p = sample.percent else { anchor = nil; continue }
            if let prior = previous, sample.session != prior.session ||
                sample.date.timeIntervalSince(prior.date) > 30 || p < (prior.percent ?? p) { anchor = nil }
            guard let start = anchor, let sp = start.percent, sp / 10 == p / 10 else {
                anchor = sample; continue
            }
            let elapsed = sample.date.timeIntervalSince(start.date)
            if p - sp >= 2 && elapsed >= 120 {
                bandRates[p / 10, default: []].append(Double(p - sp) / elapsed)
                anchor = sample
            }
        }
        for level in percent..<target {
            let fallback = baseRate * taper(Double(level))
            let rates = (bandRates[level / 10] ?? []).sorted()
            let learned = rates.isEmpty ? fallback : rates[rates.count / 2]
            // Current slowdowns dominate old faster sessions.
            let futureRate = min(fallback, learned)
            seconds += 1 / futureRate
        }
        guard seconds.isFinite, seconds < 24 * 3600 else { return nil }
        return now.addingTimeInterval(seconds)
    }
}

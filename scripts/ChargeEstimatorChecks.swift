import Foundation

@main struct ChargeEstimatorChecks {
    static func main() {
        let now = Date()
        let session = UUID()
        func history(start: Int, count: Int) -> [ChargeSample] {
            (0..<count).map { i in ChargeSample(date: now.addingTimeInterval(Double(i - count + 1) * 10),
                session: session, percent: start + i / 12, charging: true) }
        }
        let samples = history(start: 50, count: 73)
        let e80 = ChargeEstimator.eta(target: 80, now: now, percent: 56, session: session, samples: samples)!
        let e100 = ChargeEstimator.eta(target: 100, now: now, percent: 56, session: session, samples: samples)!
        assert(e80 > now && e100 > e80)
        assert(e100.timeIntervalSince(e80) > e80.timeIntervalSince(now) * 0.8, "Taper must slow the final 20 percent")
        assert(ChargeEstimator.eta(target: 80, now: now, percent: 56, session: UUID(), samples: samples) == nil)
        assert(ChargeEstimator.eta(target: 80, now: now.addingTimeInterval(90), percent: 56, session: session, samples: samples) == nil)
        assert(ChargeEstimator.eta(target: 80, now: now, percent: 80, session: session, samples: samples) == nil)
        assert(ChargeEstimator.eta(target: 80, now: now, percent: 50, session: session, samples: Array(samples.suffix(3))) == nil)
        let flat = (0..<100).map { i in ChargeSample(date: now.addingTimeInterval(Double(i - 99) * 10), session: session, percent: 70, charging: true) }
        assert(ChargeEstimator.eta(target: 80, now: now, percent: 70, session: session, samples: flat) == nil)
        var gap = samples
        gap[gap.count - 1].date = now.addingTimeInterval(120)
        assert(ChargeEstimator.eta(target: 80, now: now.addingTimeInterval(120), percent: 56, session: session, samples: gap) == nil)
        print("Charge prediction: taper, history, missing data, stale data, holds and session boundaries passed")
        var dense = (0..<6000).map { i in ChargeSample(date: now.addingTimeInterval(Double(i) / 10),
            session: session, percent: 50, watts: 5, temperature: 30, charging: true) }
        dense[2345].watts = 27
        dense[3456].temperature = 42
        dense[4200].watts = nil
        let reduced = ChargingHistory.chart(dense)
        assert(reduced.count < 1000)
        assert(reduced.contains { $0.watts == 27 }, "Keep narrow power spikes")
        assert(reduced.contains { $0.temperature == 42 }, "Keep narrow temperature spikes")
        assert(reduced.contains { $0.watts == nil }, "Keep gaps instead of drawing across them")
        assert(reduced.last?.date == dense.last?.date, "Always show the newest sample")
        print("Fast chart: spike/gap preservation, bounded rendering and latest sample passed")
    }
}

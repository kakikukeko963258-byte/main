import Foundation

@main
enum RailChecks {
    static func main() throws {
        let catalog = try JSONDecoder().decode(RailCatalog.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        precondition(catalog.lines.count > 150)
        let detector = RailDetector(catalog: catalog)
        precondition(Set(catalog.lines.map(\.id)).count == catalog.lines.count)
        let lines = Set(catalog.lines.map(\.id))
        precondition(catalog.patterns.allSatisfy { lines.contains($0.line) && $0.stops.allSatisfy { detector.stations[$0] != nil } })
        for company in ["JR-East", "TokyoMetro", "Toei", "Odakyu", "Tokyu", "Keikyu", "Keio", "Keisei", "Tobu", "Seibu", "Sotetsu"] {
            precondition(catalog.lines.contains { $0.id.hasPrefix(company + ".") })
        }
        let types = Set(catalog.patterns.map(\.type))
        precondition(types.contains("急行") && types.contains("特急") && types.contains("快速"))
        let toyoko = catalog.lines.first { $0.id == "Tokyu.Toyoko" }!
        let daikanyama = detector.stations["Tokyu.Toyoko.DaikanYama"]!
        let start = Date()
        func fix(_ t: Double, lat: Double? = nil, lon: Double? = nil, speed: Double = 0, accuracy: Double = 5) -> RailFix {
            RailFix(lat: lat ?? daikanyama.lat, lon: lon ?? daikanyama.lon, accuracy: accuracy, speed: speed, time: start.addingTimeInterval(t))
        }
        func ingest(_ value: RailFix) { precondition(detector.ingest(value, now: value.time)) }
        precondition(!detector.ingest(fix(0, accuracy: -1), now: start))
        precondition(!detector.ingest(fix(0), now: start.addingTimeInterval(60)))
        precondition(!detector.ingest(fix(0, accuracy: 500), now: start))
        ingest(fix(0)); ingest(fix(5)); ingest(fix(10)); ingest(fix(15)); ingest(fix(20))
        precondition(!detector.moving, "Stationary users must not be labelled as riding")
        precondition(detector.evidence.contains { $0.station == daikanyama.id && $0.stopped })
        let matching = detector.patterns(for: toyoko, direction: 1, progress: 1)
        precondition(!matching.isEmpty)
        precondition(matching.allSatisfy { $0.stops.contains(daikanyama.id) }, "Observed stop must reject express patterns which skip it")
        detector.reset()
        for i in 0...12 { ingest(fix(Double(i * 3), lat: daikanyama.lat + Double(i - 6) * 0.0006, speed: 22)) }
        precondition(detector.moving)
        precondition(detector.evidence.contains { $0.station == daikanyama.id && !$0.stopped })
        let passed = detector.patterns(for: toyoko, direction: 1, progress: 1)
        precondition(!passed.isEmpty)
        precondition(passed.allSatisfy { !$0.stops.contains(daikanyama.id) }, "Observed pass must reject local trains")
        detector.reset()
        ingest(fix(0, speed: 20))
        ingest(fix(60, lat: daikanyama.lat + 0.005, speed: 20))
        precondition(detector.evidence.isEmpty, "GPS gaps cannot establish a pass")
        precondition(!detector.moving)
        detector.reset()
        let yamanote = catalog.lines.first { $0.id == "JR-East.Yamanote" }!
        precondition(!detector.patterns(for: yamanote, direction: -1, progress: 28).isEmpty, "Loop wrap must support reverse direction")
        let shibuya = "Tokyu.Toyoko.Shibuya"
        let transfers = detector.transfers(at: shibuya, excluding: toyoko.id)
        precondition(transfers.contains { $0.id == "JR-East.Yamanote" })
        precondition(!transfers.contains { $0.id == toyoko.id })
        detector.reset()
        let shibuyaStation = detector.stations[shibuya]!
        ingest(fix(0, lat: shibuyaStation.lat, lon: shibuyaStation.lon))
        precondition(detector.candidates().count > 1, "Parallel lines must remain candidates")
        print("Rail checks passed: \(catalog.lines.count) lines, \(catalog.stations.count) station entries, \(catalog.patterns.count) patterns; stop/pass, GPS gaps, stale fixes, ambiguity, transfers verified")
    }
}

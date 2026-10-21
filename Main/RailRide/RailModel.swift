import Foundation

struct RailStation: Codable, Identifiable {
    let id: String
    let name: String
    let line: String
    let lon: Double
    let lat: Double
}

struct RailLine: Codable, Identifiable {
    let id: String
    let name: String
    let color: String
    let stations: [String]
    let paths: [[[Double]]]
}

struct RailPattern: Codable, Identifiable {
    let id: String
    let line: String
    let type: String
    let stops: [String]
}

struct RailCatalog: Codable {
    let revision: String
    let date: String
    let lines: [RailLine]
    let stations: [RailStation]
    let groups: [[String]]
    let patterns: [RailPattern]

    static func load() throws -> RailCatalog {
        guard let url = Bundle.main.url(forResource: "kanto-rail", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}

struct RailFix {
    let lat: Double
    let lon: Double
    let accuracy: Double
    let speed: Double
    let time: Date
}

enum RailGeometry {
    static func distance(_ lat: Double, _ lon: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let y = (lat2 - lat) * 111_195
        let x = (lon2 - lon) * 111_195 * cos((lat + lat2) * .pi / 360)
        return hypot(x, y)
    }

    // Return distance from the real track geometry, and fractional station index.
    static func projection(_ fix: RailFix, line: RailLine, stations: [String: RailStation]) -> (distance: Double, progress: Double) {
        var trackDistance = Double.infinity
        for path in line.paths {
            for (a, b) in zip(path, path.dropFirst()) where a.count >= 2 && b.count >= 2 {
                trackDistance = min(trackDistance, segment(fix, a[1], a[0], b[1], b[0]).0)
            }
        }
        var nearest = Double.infinity
        var progress = 0.0
        for i in 0..<max(0, line.stations.count - 1) {
            guard let a = stations[line.stations[i]], let b = stations[line.stations[i + 1]] else { continue }
            let (d, t) = segment(fix, a.lat, a.lon, b.lat, b.lon)
            if d < nearest { nearest = d; progress = Double(i) + t }
        }
        return (trackDistance.isFinite ? trackDistance : nearest, progress)
    }

    private static func segment(_ fix: RailFix, _ ay: Double, _ ax: Double, _ by: Double, _ bx: Double) -> (Double, Double) {
        let scale = cos(fix.lat * .pi / 180)
        let x = (ax - fix.lon) * 111_195 * scale, y = (ay - fix.lat) * 111_195
        let dx = (bx - ax) * 111_195 * scale, dy = (by - ay) * 111_195
        let length = dx * dx + dy * dy
        let t = length > 0 ? min(1, max(0, -(x * dx + y * dy) / length)) : 0
        return (hypot(x + t * dx, y + t * dy), t)
    }
}

struct RailEvidence {
    let station: String
    let stopped: Bool
    let time: Date
}

struct RailCandidate: Identifiable {
    let line: RailLine
    let distance: Double
    let progress: Double
    let direction: Int
    var id: String { line.id }
}

// Pure Foundation engine so recorded and synthetic journeys can run in CI.
final class RailDetector {
    let catalog: RailCatalog
    let stations: [String: RailStation]
    private(set) var fixes: [RailFix] = []
    private(set) var evidence: [RailEvidence] = []
    private var visits: [String: (entered: Date, last: Date, slow: Date?, stopped: Bool, fast: Bool)] = [:]

    init(catalog: RailCatalog) {
        self.catalog = catalog
        stations = Dictionary(catalog.stations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    func reset() { fixes = []; evidence = []; visits = [:] }

    @discardableResult
    func ingest(_ fix: RailFix, now: Date = Date()) -> Bool {
        guard fix.accuracy >= 0, fix.accuracy <= 100, abs(now.timeIntervalSince(fix.time)) <= 20,
              fix.lat.isFinite, fix.lon.isFinite, abs(fix.lat) <= 90, abs(fix.lon) <= 180 else { return false }
        if let last = fixes.last {
            guard fix.time > last.time else { return false }
            let gap = fix.time.timeIntervalSince(last.time)
            if gap > 45 { reset() }
            else if RailGeometry.distance(fix.lat, fix.lon, last.lat, last.lon) / gap > 110 { return false }
        }
        fixes.append(fix)
        fixes.removeAll { fix.time.timeIntervalSince($0.time) > 240 }
        evidence.removeAll { fix.time.timeIntervalSince($0.time) > 1200 }
        // Imprecise samples cannot establish a station stop or a pass.
        guard fix.accuracy <= 50 else { visits = [:]; return true }
        for station in catalog.stations {
            let d = RailGeometry.distance(fix.lat, fix.lon, station.lat, station.lon)
            if d <= 110 {
                var visit = visits[station.id] ?? (fix.time, fix.time, nil, false, true)
                if fix.time.timeIntervalSince(visit.last) > 15 { visit = (fix.time, fix.time, nil, false, true) }
                visit.last = fix.time
                if fix.speed >= 0 && fix.speed < 1.5 {
                    if visit.slow == nil { visit.slow = fix.time }
                    if fix.time.timeIntervalSince(visit.slow!) >= 15 { visit.stopped = true }
                } else { visit.slow = nil }
                // A short real stop must remain unknown rather than become a false pass.
                visit.fast = visit.fast && fix.speed >= 8
                visits[station.id] = visit
                if visit.stopped { record(station.id, stopped: true, at: fix.time) }
            } else if let visit = visits[station.id] {
                // Require continuous fixes through the entire departure; a GPS gap is never a pass.
                if fix.time.timeIntervalSince(visit.last) > 15 { visits.removeValue(forKey: station.id); continue }
                if d > 300 {
                    if visit.fast && !visit.stopped && fix.speed >= 8 { record(station.id, stopped: false, at: fix.time) }
                    visits.removeValue(forKey: station.id)
                } else {
                    var updated = visit; updated.last = fix.time; visits[station.id] = updated
                }
            }
        }
        return true
    }

    private func record(_ station: String, stopped: Bool, at time: Date) {
        guard !evidence.contains(where: { $0.station == station && time.timeIntervalSince($0.time) < 180 }) else { return }
        evidence.append(RailEvidence(station: station, stopped: stopped, time: time))
    }

    var moving: Bool {
        guard let first = fixes.first, let last = fixes.last else { return false }
        return fixes.filter { $0.speed >= 5 }.count >= 3 && RailGeometry.distance(first.lat, first.lon, last.lat, last.lon) > 300
    }

    func candidates() -> [RailCandidate] {
        guard let fix = fixes.last else { return [] }
        let history = Array(fixes.suffix(20))
        return catalog.lines.compactMap { line -> RailCandidate? in
            let current = RailGeometry.projection(fix, line: line, stations: stations)
            guard current.distance < max(180, fix.accuracy * 2) else { return nil }
            let earlier = RailGeometry.projection(history.first!, line: line, stations: stations)
            var difference = current.progress - earlier.progress
            if line.stations.first == line.stations.last {
                let count = Double(line.stations.count - 1)
                if difference > count / 2 { difference -= count }
                if difference < -count / 2 { difference += count }
            }
            let direction = abs(difference) > 0.12 ? (difference > 0 ? 1 : -1) : 0
            let average = history.map { RailGeometry.projection($0, line: line, stations: stations).distance }.reduce(0, +) / Double(history.count)
            return RailCandidate(line: line, distance: average, progress: current.progress, direction: direction)
        }.sorted { $0.distance < $1.distance }
    }

    func patterns(for line: RailLine, direction: Int, progress: Double?) -> [RailPattern] {
        let observations = evidence.filter { stations[$0.station]?.line == line.id }
        return catalog.patterns.filter { pattern in
            guard pattern.line == line.id, let span = patternSpan(pattern, line: line) else { return false }
            let (first, last, sign) = span
            if direction != 0 && direction != sign { return false }
            func inSpan(_ value: Double) -> Bool {
                let values = line.stations.first == line.stations.last ?
                    [value, value + Double(line.stations.count - 1), value - Double(line.stations.count - 1)] : [value]
                return values.contains { $0 >= Double(min(first, last)) - 0.2 && $0 <= Double(max(first, last)) + 0.2 }
            }
            if let progress, !inSpan(progress) { return false }
            for observation in observations {
                guard let index = line.stations.firstIndex(of: observation.station), inSpan(Double(index)) else { return false }
                if pattern.stops.contains(observation.station) != observation.stopped { return false }
            }
            return true
        }
    }

    private func patternSpan(_ pattern: RailPattern, line: RailLine) -> (Int, Int, Int)? {
        let indices = pattern.stops.compactMap { line.stations.firstIndex(of: $0) }
        guard indices.count == pattern.stops.count, let first = indices.first else { return nil }
        let loop = line.stations.first == line.stations.last
        let count = line.stations.count - 1
        var position = first
        var sign = 0
        for (a, b) in zip(indices, indices.dropFirst()) {
            var step = b - a
            if loop && step > count / 2 { step -= count }
            if loop && step < -count / 2 { step += count }
            if step != 0 && sign == 0 { sign = step > 0 ? 1 : -1 }
            position += step
        }
        guard sign != 0 else { return nil }
        return (first, position, sign)
    }

    func transfers(at stationID: String, excluding lineID: String) -> [RailLine] {
        let related = Set(catalog.groups.filter { $0.contains(stationID) }.flatMap { $0 })
        let lines = Set(related.compactMap { stations[$0]?.line })
        return catalog.lines.filter { $0.id != lineID && lines.contains($0.id) }.sorted { $0.name < $1.name }
    }
}

import CoreLocation
import SwiftUI

@MainActor
final class RailRideStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var catalog: RailCatalog?
    @Published private(set) var detector: RailDetector?
    @Published private(set) var candidates: [RailCandidate] = []
    @Published private(set) var lastFix: RailFix?
    @Published private(set) var running = false
    @Published private(set) var message = "位置情報を使って乗車中の路線を探します"
    @Published var selectedLine: String?
    @Published var selectedPattern: String?
    @Published var manualDirection = 0
    private let manager = CLLocationManager()
    private var lastProcessed = Date.distantPast
    private var wantsLocation = false

    override init() {
        super.init()
        do {
            let catalog = try RailCatalog.load()
            self.catalog = catalog
            detector = RailDetector(catalog: catalog)
        } catch { message = "路線データを読み込めませんでした。アプリを開き直してください。" }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        guard catalog != nil else { return }
        wantsLocation = true
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            running = true
            message = "GPSを受信中。数駅分の移動で候補を絞ります"
            manager.startUpdatingLocation()
        case .denied, .restricted:
            message = "位置情報が許可されていません。設定で位置情報を許可するか、路線を手動で選んでください。"
        @unknown default: message = "位置情報を利用できません"
        }
    }

    func stop() {
        wantsLocation = false
        running = false
        manager.stopUpdatingLocation()
        message = "検知を停止しています"
    }

    func reset() {
        detector?.reset(); candidates = []; lastFix = nil
        selectedLine = nil; selectedPattern = nil; manualDirection = 0
        lastProcessed = .distantPast
    }

    func chooseLine(_ id: String?) {
        selectedLine = id; selectedPattern = nil; manualDirection = 0
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if wantsLocation { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard running, let location = locations.last, location.timestamp.timeIntervalSince(lastProcessed) >= 3 else { return }
        let fix = RailFix(lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                          accuracy: location.horizontalAccuracy, speed: location.speed, time: location.timestamp)
        guard detector?.ingest(fix) == true else {
            message = "GPSの精度が不足しています。測位が改善するまで候補を更新しません。"
            return
        }
        lastProcessed = fix.time; lastFix = fix
        candidates = detector?.candidates() ?? []
        message = candidates.isEmpty ? "収録路線から離れているか、測位が不安定です" :
            (detector?.moving == true ? "移動と停車・通過を照合中（推定）" : "移動待ち。近くの路線を候補として表示します")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        message = "位置情報を取得できません。地下などでは地上に出てから再開します。"
    }

    var automaticLine: RailCandidate? {
        guard detector?.moving == true, let first = candidates.first else { return nil }
        guard candidates.count == 1 || candidates[1].distance - first.distance > 40 else { return nil }
        return first
    }

    var line: RailLine? {
        if let id = selectedLine { return catalog?.lines.first { $0.id == id } }
        return automaticLine?.line
    }

    var direction: Int { manualDirection != 0 ? manualDirection : candidates.first { $0.id == line?.id }?.direction ?? 0 }
    var progress: Double? { candidates.first { $0.id == line?.id }?.progress }
    var patterns: [RailPattern] {
        guard let line, let detector else { return [] }
        return detector.patterns(for: line, direction: direction, progress: progress)
    }
    var activePattern: RailPattern? {
        guard let id = selectedPattern else { return nil }
        return catalog?.patterns.first { $0.id == id && $0.line == line?.id }
    }
    var typeLabel: String {
        if let activePattern { return activePattern.type + "（手動）" }
        let types = Set(patterns.map(\.type))
        let observations = detector?.evidence.filter { detector?.stations[$0.station]?.line == line?.id } ?? []
        if observations.count >= 2 && direction != 0 && types.count == 1 { return types.first! + " の可能性" }
        return "種別を判別中"
    }
    var displayedStations: [RailStation] {
        guard let line, let detector else { return [] }
        let ids = activePattern?.stops ?? (direction == -1 ? Array(line.stations.reversed()) : line.stations)
        // Keep both occurrences of a loop terminus; rows use their sequence index as identity.
        return ids.compactMap { detector.stations[$0] }
    }
}

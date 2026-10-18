import Foundation
import ActivityKit

struct ChargeState: Codable, Hashable {
    var date: Date
    var percent: Int?
    var watts: Double?
    var temperature: Double?
    var connected: Bool
    var charging: Bool
    var paused: Bool
    var eta80: Date?
    var eta100: Date?
    var powerSource: String
    static let empty = ChargeState(date: .distantPast, connected: false, charging: false,
                                   paused: true, powerSource: "取得不可")
    var powerText: String { watts.map { String(format: "%.2f W", $0) } ?? "取得不可" }
    var percentText: String { percent.map { "\($0)%" } ?? "—%" }
    func isStale(at now: Date) -> Bool { paused || now.timeIntervalSince(date) > 20 }
}

struct ChargingAttributes: ActivityAttributes {
    typealias ContentState = ChargeState
    var name: String = "main 充電モニター"
}

enum ChargingCache {
    static let suite: String = {
        let base = "group.com.kakikukeko.main.pcfilebridge"
        var groups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url),
           let start = data.range(of: Data("<plist".utf8)),
           let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
           let profile = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
           let entitlements = profile["Entitlements"] as? [String: Any] {
            groups += entitlements["com.apple.security.application-groups"] as? [String] ?? []
        }
        return groups.first { ($0 == base || $0.hasPrefix(base + ".")) &&
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? base
    }()
    static func load() -> ChargeState {
        guard let data = UserDefaults(suiteName: suite)?.data(forKey: "charging-snapshot"),
              let state = try? JSONDecoder().decode(ChargeState.self, from: data) else { return .empty }
        return state
    }
    static func save(_ state: ChargeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults(suiteName: suite)?.set(data, forKey: "charging-snapshot")
    }
}

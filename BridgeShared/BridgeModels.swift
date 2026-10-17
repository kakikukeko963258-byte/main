import Foundation

struct BridgeItem: Codable, Identifiable, Hashable {
    let id: String
    let parentId: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modifiedUtc: Date
    let version: String
    var readOnly: Bool? = nil
}

struct ItemPage: Codable {
    let items: [BridgeItem]
    let next: String?
}

struct PairRequest: Encodable {
    let code: String
    let deviceName: String
}

struct PairResponse: Decodable {
    let deviceId: String
    let token: String
    let serverName: String
    let port: Int
}

struct CreateItemRequest: Encodable {
    let parentId: String
    let name: String
    let isDirectory: Bool
}

struct ModifyItemRequest: Encodable {
    let name: String?
    let parentId: String?
}

struct RemoteChange: Codable {
    let sequence: Int64
    let parentId: String
    let itemId: String
    let kind: String
}

struct ChangePage: Codable {
    let changes: [RemoteChange]
    let latestSequence: Int64
}

struct SavedServer: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: String
    var deviceId: String
    var addedAt: Date
}

enum BridgeConstants {
    // AltStore can namespace app groups during re-signing. Use only this app's
    // authorized group, and let iOS validate the container membership.
    static let appGroup: String = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "PCFileBridgeAppGroup") as? String ?? "group.com.kakikukeko.main.pcfilebridge"
        let base = "group.com.kakikukeko.main.pcfilebridge"
        let authorized = (Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? provisionedGroups())
            .filter { $0 == base || $0.hasPrefix(base + ".") }
        let candidates = authorized.isEmpty ? [configured] :
            authorized.sorted { ($0 == configured ? 0 : 1) < ($1 == configured ? 0 : 1) }
        return candidates.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil } ?? configured
    }()

    private static func provisionedGroups() -> [String] {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return [] }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }
}

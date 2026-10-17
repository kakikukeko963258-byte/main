import Foundation

struct ConnectionSetup: Decodable {
    let version: Int
    let setupId: String
    let baseURL: String
    let code: String
    let expiresUtc: Date
    let serverName: String

    static func dataFromQR(_ value: String) throws -> Data {
        guard value.utf8.count <= 12000,
              let url = URLComponents(string: value), url.scheme == "pcfilebridge", url.host == "pair",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.path.isEmpty, let query = url.queryItems, query.count == 1, query[0].name == "data",
              let encoded = query[0].value else { throw SetupError.invalid }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw SetupError.invalid }
        _ = try decode(data)
        return data
    }

    static func decode(_ data: Data) throws -> ConnectionSetup {
        guard data.count <= 8192 else { throw SetupError.invalid }
        let setup = try JSONDecoder.bridge.decode(ConnectionSetup.self, from: data)
        guard setup.version == 1, !setup.setupId.isEmpty,
              setup.code.utf8.count == 6, setup.code.utf8.allSatisfy({ (48...57).contains($0) }),
              let url = URLComponents(string: setup.baseURL),
              url.scheme == "http" || url.scheme == "https", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/",
              let host = url.host, privateIPv4(host),
              (1...65535).contains(url.port ?? (url.scheme == "https" ? 443 : 80)) else { throw SetupError.invalid }
        guard setup.expiresUtc > Date() else { throw SetupError.expired }
        return setup
    }

    private static func privateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let bytes = parts.compactMap { UInt8($0) }
        guard parts.count == 4, bytes.count == 4 else { return false }
        return bytes[0] == 10 || (bytes[0] == 172 && (16...31).contains(bytes[1])) ||
            (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 100 && (64...127).contains(bytes[1]))
    }
}

enum SetupError: LocalizedError {
    case invalid, expired
    var errorDescription: String? {
        switch self {
        case .invalid: return "PCの接続設定を読み取れません。PC側で設定を書き出し直してください。"
        case .expired: return "初回設定の期限が切れています。PC側で設定を更新してください。"
        }
    }
}

enum ConnectionStatus: Equatable {
    case checking, connected, offline, needsPairing
    var title: String {
        switch self {
        case .checking: return "接続を確認中…"
        case .connected: return "接続済み・入力不要"
        case .offline: return "再接続待ち：PCとTailscaleを確認してください"
        case .needsPairing: return "接続情報の更新が必要です"
        }
    }
    var symbol: String {
        switch self {
        case .checking: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .offline: return "network.slash"
        case .needsPairing: return "key.fill"
        }
    }
}

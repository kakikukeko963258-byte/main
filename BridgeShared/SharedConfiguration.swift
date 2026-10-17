import Foundation

enum SharedConfiguration {
    private static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BridgeConstants.appGroup) }
    private static var serversFile: URL? { container?.appendingPathComponent("servers.json") }

    static func loadServers() -> [SavedServer] {
        if let file = serversFile, let data = try? Data(contentsOf: file),
           let servers = try? JSONDecoder.bridge.decode([SavedServer].self, from: data) { return servers }
        guard !Bundle.main.bundleURL.pathExtension.elementsEqual("appex"),
              let backup = UserDefaults.standard.data(forKey: "PCFileBridge.savedServersBackup"),
              let servers = try? JSONDecoder.bridge.decode([SavedServer].self, from: backup) else { return [] }
        try? saveServers(servers)
        return servers
    }

    static func saveServers(_ servers: [SavedServer]) throws {
        guard let file = serversFile else { throw BridgeError.sharedContainerUnavailable }
        let data = try JSONEncoder.bridge.encode(servers)
        try data.write(to: file, options: .atomic)
        if Bundle.main.bundleURL.pathExtension != "appex" {
            UserDefaults.standard.set(data, forKey: "PCFileBridge.savedServersBackup")
        }
    }

    static func server(forDomain id: String) -> SavedServer? { loadServers().first { $0.id == id } }
}

enum MaterializedItemStore {
    private static let lock = NSLock()
    private static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BridgeConstants.appGroup)?.appendingPathComponent("materialized-items.json")
    }

    static func load(domainID: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [] }
        return map[domainID] ?? []
    }

    static func save(_ identifiers: Set<String>, domainID: String) {
        lock.lock(); defer { lock.unlock() }
        guard let fileURL else { return }
        var map = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        map[domainID] = Array(identifiers).sorted()
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: fileURL, options: .atomic) }
    }
}

enum SharedTokenStore {
    private static let lock = NSLock()
    private static var tokensFile: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BridgeConstants.appGroup)?.appendingPathComponent("tokens.json")
    }
    private static var privateBackup: URL? {
        guard Bundle.main.bundleURL.pathExtension != "appex",
              let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let directory = folder.appendingPathComponent("PCFileBridge", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("connection-keys.json")
    }

    static func save(_ token: String, for serverId: String) throws {
        lock.lock(); defer { lock.unlock() }
        guard let file = tokensFile else { throw BridgeError.sharedContainerUnavailable }
        var tokens = readTokens(from: file)
        tokens[serverId] = token
        try writeTokens(tokens, to: file)
        if let backup = privateBackup { try writeTokens(tokens, to: backup) }
    }

    static func load(for serverId: String) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let file = tokensFile else { throw BridgeError.sharedContainerUnavailable }
        if let token = readTokens(from: file)[serverId] { return token }
        guard let backup = privateBackup, let token = readTokens(from: backup)[serverId] else { throw BridgeError.tokenNotFound }
        var tokens = readTokens(from: file)
        tokens[serverId] = token
        try writeTokens(tokens, to: file)
        return token
    }

    static func delete(for serverId: String) {
        lock.lock(); defer { lock.unlock() }
        guard let file = tokensFile else { return }
        var tokens = readTokens(from: file)
        tokens.removeValue(forKey: serverId)
        try? writeTokens(tokens, to: file)
        if let backup = privateBackup {
            var saved = readTokens(from: backup)
            saved.removeValue(forKey: serverId)
            try? writeTokens(saved, to: backup)
        }
    }

    private static func readTokens(from file: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: file),
              let tokens = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return tokens
    }

    private static func writeTokens(_ tokens: [String: String], to file: URL) throws {
        let data = try JSONEncoder().encode(tokens)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

enum BridgeError: LocalizedError {
    case sharedContainerUnavailable
    case invalidServerAddress
    case invalidResponse
    case http(Int, String)
    case tokenNotFound

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable: return "共有コンテナを利用できません。署名設定を確認してください。"
        case .invalidServerAddress: return "サーバーアドレスを確認してください。"
        case .invalidResponse: return "サーバーからの応答を読み取れませんでした。"
        case .http(let code, let message): return "サーバーエラー (\(code): \(message))"
        case .tokenNotFound: return "ペアリング情報が見つかりません。PCと再ペアリングしてください。"
        }
    }
}

extension JSONDecoder {
    static var bridge: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer(); let value = try container.decode(String.self)
            let normalized = value.replacingOccurrences(
                of: #"(\.\d{1,3})\d+(?=Z|[+-]\d{2}:\d{2}$)"#,
                with: "$1",
                options: .regularExpression
            )
            let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) ?? fractional.date(from: normalized) { return date }
            let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: value) ?? plain.date(from: normalized) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
        }
        return decoder
    }
}
extension JSONEncoder {
    static var bridge: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}

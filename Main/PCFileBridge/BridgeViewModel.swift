import Foundation
import FileProvider
import UIKit
import Combine

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published var servers: [SavedServer] = []
    @Published var address = ""
    @Published var pairingCode = ""
    @Published var isWorking = false
    @Published var message: String?
    @Published var error: String?
    @Published var connectionStates: [String: ConnectionStatus] = [:]
    @Published var canRetrySetup = false
    @Published var filesRegistrationErrors: [String: String] = [:]
    private var preparedSetup: ConnectionSetup?
    private var isRefreshingConnections = false
    private var filesRegistrationAttempts: Set<String> = []

    init() { servers = SharedConfiguration.loadServers() }

    @discardableResult
    func pair() async -> Bool {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pairingCode.count == 6 else { error = "PCのアドレスと6桁コードを入力してください。"; return false }
        isWorking = true; error = nil; message = nil
        defer { isWorking = false }
        var stage = "PCとの登録通信"
        do {
            let response = try await BridgeClient.pair(baseURL: address, code: pairingCode, deviceName: UIDevice.current.name)
            let baseURL = BridgeClient.normalize(address)
            let previous = servers.first { $0.baseURL == baseURL }
            let server = SavedServer(id: previous?.id ?? UUID().uuidString.lowercased(), name: response.serverName, baseURL: baseURL, deviceId: response.deviceId, addedAt: previous?.addedAt ?? Date())
            stage = "接続キーの保存"
            try SharedTokenStore.save(response.token, for: server.id)
            let updatedServers = [server] + servers.filter { $0.id != server.id }
            stage = "PC設定の保存"
            do {
                try SharedConfiguration.saveServers(updatedServers)
            } catch {
                SharedTokenStore.delete(for: server.id)
                throw error
            }
            servers = updatedServers
            address = ""; pairingCode = ""
            await refreshConnections()
            if filesRegistrationErrors[server.id] == nil {
                message = "\(server.name)を登録しました。次回から入力なしで再接続します。"
            }
            return true
        } catch { self.error = Self.describe(error, stage: stage); return false }
    }

    func registerInFiles(_ server: SavedServer) async {
        filesRegistrationAttempts.insert(server.id)
        do {
            try await addDomain(for: server)
            filesRegistrationErrors[server.id] = nil
        } catch {
            filesRegistrationErrors[server.id] = Self.describe(error, stage: "Filesへの登録")
        }
    }

    private static func describe(_ error: Error, stage: String) -> String {
        if let decoding = error as? DecodingError {
            let field: String
            switch decoding {
            case .keyNotFound(let key, _): field = key.stringValue
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                field = context.codingPath.map(\.stringValue).joined(separator: ".")
            @unknown default: field = ""
            }
            return "\(stage)：応答の形式を読み取れません（\(field.isEmpty ? "JSON" : field)）。"
        }
        let details = error as NSError
        return "\(stage)：\(error.localizedDescription)（\(details.domain) / \(details.code)）"
    }

    func prepareConnection() async {
        guard let url = Bundle.main.url(forResource: "PCFileBridgeSetup", withExtension: "json") else { return }
        do {
            // A successful setup remains valid after its short-lived code expires.
            let data = try Data(contentsOf: url)
            let metadata = try JSONDecoder.bridge.decode(ConnectionSetup.self, from: data)
            if UserDefaults.standard.string(forKey: "PCFileBridge.completedSetup") == metadata.setupId && !servers.isEmpty { return }
            if servers.isEmpty {
                UserDefaults.standard.removeObject(forKey: "PCFileBridge.attemptedSetup")
                UserDefaults.standard.removeObject(forKey: "PCFileBridge.completedSetup")
            }
            if servers.contains(where: { $0.baseURL == BridgeClient.normalize(metadata.baseURL) }) { return }
            let setup = try ConnectionSetup.decode(data)
            preparedSetup = setup
            canRetrySetup = true
            if UserDefaults.standard.string(forKey: "PCFileBridge.attemptedSetup") != setup.setupId {
                await retrySetup()
            }
        } catch { if servers.isEmpty { self.error = error.localizedDescription } }
    }

    func importSetup(_ data: Data) async {
        do {
            preparedSetup = try ConnectionSetup.decode(data)
            canRetrySetup = true
            await retrySetup()
        } catch { self.error = error.localizedDescription }
    }

    func retrySetup() async {
        guard !isWorking, let setup = preparedSetup else { return }
        guard setup.expiresUtc > Date() else { error = SetupError.expired.localizedDescription; return }
        UserDefaults.standard.set(setup.setupId, forKey: "PCFileBridge.attemptedSetup")
        address = setup.baseURL
        pairingCode = setup.code
        if await pair() {
            UserDefaults.standard.set(setup.setupId, forKey: "PCFileBridge.completedSetup")
            preparedSetup = nil
            canRetrySetup = false
        }
    }

    func refreshConnections() async {
        guard !isRefreshingConnections else { return }
        isRefreshingConnections = true
        defer { isRefreshingConnections = false }
        for server in servers {
            if Task.isCancelled { return }
            if connectionStates[server.id] == nil { connectionStates[server.id] = .checking }
            do {
                let client = BridgeClient(server: server, token: try SharedTokenStore.load(for: server.id))
                try await client.checkConnection()
                connectionStates[server.id] = .connected
                if !filesRegistrationAttempts.contains(server.id) { await registerInFiles(server) }
            } catch BridgeError.tokenNotFound { connectionStates[server.id] = .needsPairing }
            catch BridgeError.http(401, _) { connectionStates[server.id] = .needsPairing }
            catch { connectionStates[server.id] = .offline }
        }
    }

    func test(_ server: SavedServer) async {
        isWorking = true; error = nil; message = nil
        defer { isWorking = false }
        do {
            let client = BridgeClient(server: server, token: try SharedTokenStore.load(for: server.id))
            message = "\(server.name): \(try await client.health())"
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ server: SavedServer) async {
        isWorking = true; error = nil; message = nil
        defer { isWorking = false }
        do {
            let currentDomains = try await Self.domains()
            let domain = currentDomains.first { $0.identifier.rawValue == server.id }
            if let domain { try await NSFileProviderManager.remove(domain) }
            SharedTokenStore.delete(for: server.id)
            servers.removeAll { $0.id == server.id }
            try SharedConfiguration.saveServers(servers)
            message = "\(server.name)を削除しました。"
        } catch { self.error = error.localizedDescription }
    }

    private func addDomain(for server: SavedServer) async throws {
        let current = try await Self.domains()
        if current.contains(where: { $0.identifier.rawValue == server.id }) { return }
        let domain = NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(rawValue: server.id), displayName: server.name)
        try await NSFileProviderManager.add(domain)
    }

    private static func domains() async throws -> [NSFileProviderDomain] {
        try await withCheckedThrowingContinuation { continuation in
            NSFileProviderManager.getDomainsWithCompletionHandler { domains, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: domains) }
            }
        }
    }
}

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
    private var preparedSetup: ConnectionSetup?
    private var isRefreshingConnections = false

    init() { servers = SharedConfiguration.loadServers() }

    @discardableResult
    func pair() async -> Bool {
        guard !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pairingCode.count == 6 else { error = "PCのアドレスと6桁コードを入力してください。"; return false }
        isWorking = true; error = nil; message = nil
        defer { isWorking = false }
        do {
            let response = try await BridgeClient.pair(baseURL: address, code: pairingCode, deviceName: UIDevice.current.name)
            let server = SavedServer(id: UUID().uuidString.lowercased(), name: response.serverName, baseURL: BridgeClient.normalize(address), deviceId: response.deviceId, addedAt: Date())
            try SharedTokenStore.save(response.token, for: server.id)
            let updatedServers = [server] + servers
            do {
                try SharedConfiguration.saveServers(updatedServers)
                try await addDomain(for: server)
                servers = updatedServers
            } catch {
                SharedTokenStore.delete(for: server.id)
                try? SharedConfiguration.saveServers(servers)
                throw error
            }
            address = ""; pairingCode = ""
            message = "\(server.name)を登録しました。次回から入力なしで再接続します。"
            connectionStates[server.id] = .connected
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func prepareConnection() async {
        guard let url = Bundle.main.url(forResource: "PCFileBridgeSetup", withExtension: "json") else { return }
        do {
            // A successful setup remains valid after its short-lived code expires.
            let data = try Data(contentsOf: url)
            let metadata = try JSONDecoder.bridge.decode(ConnectionSetup.self, from: data)
            if UserDefaults.standard.string(forKey: "PCFileBridge.completedSetup") == metadata.setupId { return }
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

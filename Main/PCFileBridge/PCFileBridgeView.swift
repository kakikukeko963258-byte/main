import SwiftUI
import UniformTypeIdentifiers

struct PCFileBridgeView: View {
    let onHome: () -> Void
    @State private var showSetupImporter = false
    @State private var showQRScanner = false
    @State private var showManualPairing = false
    @StateObject private var model = BridgeViewModel()
    @StateObject private var discovery = PCDiscovery()
    @StateObject private var changeMonitor = ChangeMonitor()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("初回設定後は、外出先でも保存したPCへ自動で再接続します。PCを起動し、両方のTailscaleをオンにしてください。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button { showQRScanner = true } label: { Label("QRコードで接続", systemImage: "qrcode.viewfinder") }
                        .disabled(model.isWorking)
                    Button("設定ファイルを読み込む") { showSetupImporter = true }
                    if model.canRetrySetup {
                        Button("初回の接続を再試行") { Task { await model.retrySetup() } }.disabled(model.isWorking)
                    }
                }
                if model.servers.isEmpty || showManualPairing {
                Section("Windows PCとペアリング") {
                    TextField("PCのアドレス 例: 192.168.1.20:8765", text: $model.address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("PC画面の6桁コード", text: $model.pairingCode)
                        .keyboardType(.numberPad).onChange(of: model.pairingCode) { value in model.pairingCode = String(value.filter(\.isNumber).prefix(6)) }
                    Button { Task { await model.pair() } } label: {
                        if model.isWorking { ProgressView().frame(maxWidth: .infinity) }
                        else { Text("ペアリングしてFilesに追加").frame(maxWidth: .infinity) }
                    }.disabled(model.isWorking)
                }

                } else {
                    Section { Button("別のPCを追加") { showManualPairing = true } }
                }

                Section {
                    if discovery.computers.isEmpty {
                        Text("同じWi-Fi上のPCを検索しています…").foregroundStyle(.secondary)
                    } else {
                        ForEach(discovery.computers) { pc in
                            Button {
                                model.address = pc.address
                            } label: {
                                HStack { VStack(alignment: .leading) { Text(pc.name); Text(pc.address).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.left") }
                            }.buttonStyle(.plain)
                        }
                    }
                } header: { Text("ネットワーク上で見つかったPC") }

                Section("保存済みのPC") {
                    if model.servers.isEmpty { Text("ペアリングしたPCはありません。").foregroundStyle(.secondary) }
                    ForEach(model.servers) { server in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(server.name).font(.headline)
                            Text(server.baseURL).font(.caption).foregroundStyle(.secondary)
                            let status = model.connectionStates[server.id] ?? .checking
                            Label(status.title, systemImage: status.symbol).font(.caption)
                                .foregroundStyle(status == .connected ? Color.green : Color.secondary)
                            NavigationLink("ファイルを閲覧") {
                                RemoteFolderView(server: server, parentId: "root", title: server.name)
                            }
                            if let registrationError = model.filesRegistrationErrors[server.id] {
                                Text(registrationError).font(.caption).foregroundStyle(.red)
                                Button("Filesへの登録を再試行") { Task { await model.registerInFiles(server) } }
                            }
                            HStack {
                                Button("接続テスト") { Task { await model.test(server) } }
                                Spacer()
                                Button("Filesから削除", role: .destructive) { Task { await model.remove(server) } }
                            }.font(.subheadline)
                        }.padding(.vertical, 4)
                    }
                }

                if let message = model.message { Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
                if let error = model.error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
                Section {
                    Text("PC File Bridgeは選択したフォルダーだけを共有します。接続後、Filesアプリの「ブラウズ」→「場所」にPC名が表示されます。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("PC File Bridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: onHome) { Image(systemName: "chevron.left") }
                        .accessibilityLabel("ホームへ戻る")
                }
            }
            .task {
                await model.prepareConnection()
                discovery.start()
                if scenePhase == .active { changeMonitor.start(servers: model.servers) }
                while !Task.isCancelled {
                    if scenePhase == .active { await model.refreshConnections() }
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                }
            }
            .fileImporter(isPresented: $showSetupImporter, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8192 else { throw SetupError.invalid }
                    let data = try Data(contentsOf: url)
                    Task { await model.importSetup(data) }
                } catch { model.error = error.localizedDescription }
            }
            .sheet(isPresented: $showQRScanner) {
                NavigationStack {
                    PairingQRScanner { result in
                        showQRScanner = false
                        switch result {
                        case .success(let value):
                            do {
                                let data = try ConnectionSetup.dataFromQR(value)
                                Task { await model.importSetup(data) }
                            } catch { model.error = error.localizedDescription }
                        case .failure(let error): model.error = error.localizedDescription
                        }
                    }
                    .navigationTitle("PCのQRコードを読み取る")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { showQRScanner = false } } }
                }
            }
            .onChange(of: model.servers) { servers in
                if scenePhase == .active { changeMonitor.start(servers: servers) }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { changeMonitor.start(servers: model.servers) }
                else { changeMonitor.stop() }
            }
            .onDisappear { discovery.stop(); changeMonitor.stop() }
        }
    }
}

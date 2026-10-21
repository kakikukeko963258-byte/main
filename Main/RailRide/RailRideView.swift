import SwiftUI

struct RailRideView: View {
    let onHome: () -> Void
    @StateObject private var store = RailRideStore()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLines = false
    @State private var showPatterns = false
    @State private var showCoverage = false
    @State private var search = ""
    @State private var resumeAfterBackground = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("関東 乗車ナビ", systemImage: "tram.fill").font(.title2.bold())
                        Text(store.line?.name ?? "乗車中の路線を探す").font(.title.bold())
                            .accessibilityIdentifier("rail-line")
                        Text(store.line == nil ? "並走する路線は候補から選べます" : store.typeLabel)
                            .font(.headline).foregroundStyle(.cyan).accessibilityIdentifier("rail-type")
                        Text(store.message).font(.subheadline).foregroundStyle(.secondary)
                        if let fix = store.lastFix {
                            TimelineView(.periodic(from: .now, by: 5)) { context in
                                let stale = context.date.timeIntervalSince(fix.time) > 30
                                Text(stale ? "GPS未更新：表示は前回の候補です" : "GPS精度 ±\(Int(fix.accuracy))m ・ \(Int(max(0, fix.speed) * 3.6))km/h")
                                    .font(.caption).foregroundStyle(stale ? .orange : .secondary)
                            }
                        }
                        Button(store.running ? "検知を停止" : "自動検知を開始") {
                            if store.running { store.stop() } else { store.start() }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("rail-start")
                    }.padding(.vertical, 8)
                }
                Section("路線・列車種別") {
                    Button { showLines = true } label: { Label("路線を選ぶ・補正", systemImage: "list.bullet") }
                        .accessibilityIdentifier("rail-choose-line")
                    if store.line != nil {
                        Picker("進行方向", selection: $store.manualDirection) {
                            Text("自動").tag(0); Text("駅順 →").tag(1); Text("← 駅順").tag(-1)
                        }.onChange(of: store.manualDirection) { _ in store.selectedPattern = nil }
                        Button("種別・行き先を選ぶ・補正") { showPatterns = true }
                            .accessibilityIdentifier("rail-choose-pattern")
                        if let last = store.displayedStations.last { Text("表示方向の終点：\(last.name)").font(.caption) }
                    }
                    if store.selectedLine != nil || store.selectedPattern != nil {
                        Button("自動推定に戻す") { store.chooseLine(nil) }
                    }
                }
                if !store.nextStops.isEmpty {
                    Section("次の停車駅候補（推定）") {
                        ForEach(store.nextStops) { station in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(station.name).font(.title3.bold())
                                let transfers = store.detector?.transfers(at: station.id, excluding: store.line?.id ?? "") ?? []
                                if !transfers.isEmpty { Text(transfers.map(\.name).joined(separator: "・")).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if !store.candidates.isEmpty {
                    Section("近くの路線候補（乗車は未確定）") {
                        ForEach(store.candidates.prefix(8)) { candidate in
                            Button { store.chooseLine(candidate.id) } label: {
                                HStack {
                                    Text(candidate.line.name)
                                    Spacer()
                                    Text("約\(Int(candidate.distance))m").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if let line = store.line {
                    Section(store.activePattern == nil ? "路線の駅と停車候補" : "選択した列車の停車駅") {
                        if store.activePattern == nil {
                            Text("種別・方向・行き先の候補を照合しています。駅をタップすると乗り換え路線が見られます。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(Array(store.displayedStations.enumerated()), id: \.offset) { index, station in
                            NavigationLink {
                                stationDetail(station, line: line)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "circle.inset.filled").foregroundStyle(.cyan).padding(.top, 3)
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack { Text(station.name).font(.headline); Spacer(); Text(stopLabel(station)).font(.caption).foregroundStyle(.secondary) }
                                        let transfers = store.detector?.transfers(at: station.id, excluding: line.id) ?? []
                                        if !transfers.isEmpty {
                                            Text(transfers.map(\.name).joined(separator: "・")).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.accessibilityIdentifier("rail-station-\(index)")
                        }
                    }
                }
                Section {
                    Text("GPSの移動と停車パターンによる推定です。急行・快速・特急などは停車・通過の観測が増えると候補が絞られます。同じ停車駅の種別、地下、並走区間では特定できないことがあります。")
                    Text("収録データにない臨時列車・運休・ダイヤ変更・直通先での種別変更は反映されません。車内案内も確認してください。画面を閉じると測位を停止します。")
                    Button("収録路線・データの出典") { showCoverage = true }
                    Button("乗り換えた・観測をリセット") { store.reset() }
                }.font(.caption)
            }
            .navigationTitle("乗車ナビ").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("ホームへ戻る", action: onHome) } }
            .sheet(isPresented: $showLines) { linePicker }
            .sheet(isPresented: $showPatterns) { patternPicker }
            .sheet(isPresented: $showCoverage) { coverage }
            .onDisappear { store.stop() }
            .onChange(of: scenePhase) { phase in
                if phase == .background { resumeAfterBackground = store.running; store.stop() }
                if phase == .active && resumeAfterBackground { resumeAfterBackground = false; store.start() }
            }
        }
    }

    private func stopLabel(_ station: RailStation) -> String {
        if store.activePattern != nil { return "停車（手動選択）" }
        let patterns = store.patterns
        guard !patterns.isEmpty, store.direction != 0 else { return "種別・方向未確定" }
        let count = patterns.filter { $0.stops.contains(station.id) }.count
        if count == patterns.count { return "停車候補" }
        if count == 0 { return "通過候補" }
        return "停車／通過 未確定"
    }

    private func stationDetail(_ station: RailStation, line: RailLine) -> some View {
        List {
            Section("乗り換えできる路線") {
                let transfers = store.detector?.transfers(at: station.id, excluding: line.id) ?? []
                if transfers.isEmpty { Text("収録された乗り換え路線はありません") }
                ForEach(transfers) { transfer in
                    Button(transfer.name) { store.chooseLine(transfer.id) }
                }
            }
            Text("乗り換えには改札外の徒歩移動が必要な場合があります。駅構内の案内を確認してください。")
                .font(.caption).foregroundStyle(.secondary)
        }.navigationTitle(station.name)
    }

    private var linePicker: some View {
        NavigationStack {
            List {
                Button("自動推定") { store.chooseLine(nil); showLines = false }
                ForEach((store.catalog?.lines ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }) { line in
                    Button { store.chooseLine(line.id); showLines = false } label: {
                        VStack(alignment: .leading) { Text(line.name); Text(line.id.components(separatedBy: ".").first ?? "").font(.caption).foregroundStyle(.secondary) }
                    }.accessibilityIdentifier("rail-line-\(line.id)")
                }
            }.searchable(text: $search, prompt: "路線名・会社名")
                .navigationTitle("路線を選ぶ")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showLines = false } } }
        }
    }

    private var patternPicker: some View {
        NavigationStack {
            List {
                Button("自動推定") { store.selectedPattern = nil; showPatterns = false }
                Text("同じ種別でも行き先・停車駅が異なるパターンがあります。停車駅を確認して選んでください。")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(manualPatterns) { pattern in
                    Button {
                        store.selectedPattern = pattern.id; showPatterns = false
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(pattern.type) ・ \(stationName(pattern.stops.last!))方面")
                            Text("\(stationName(pattern.stops.first!))発 / \(pattern.stops.count)駅").font(.caption)
                            Text(pattern.stops.map(stationName).joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("rail-pattern-\(pattern.id)")
                }
                if manualPatterns.isEmpty { Text("この路線には収録された停車パターンがありません") }
            }.navigationTitle("種別・行き先")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showPatterns = false } } }
        }
    }

    private var manualPatterns: [RailPattern] {
        (store.catalog?.patterns ?? []).filter { $0.line == store.line?.id }.sorted {
            if $0.type != $1.type { return $0.type < $1.type }
            return $0.stops.count > $1.stops.count
        }
    }
    private func stationName(_ id: String) -> String { store.detector?.stations[id]?.name ?? id }

    private var coverage: some View {
        NavigationStack {
            List {
                Section("オフライン収録データ") {
                    Text("関東1都6県を中心とした\(store.catalog?.lines.count ?? 0)路線。周辺県へ延びる路線も含みます。未収録区間では自動検知できません。")
                    Text("データ取得日：\(store.catalog?.date ?? "—")（営業日・最新ダイヤの保証ではありません）")
                    Link("Mini Tokyo 3D / Akihiko Kusanagi", destination: URL(string: "https://github.com/nagix/mini-tokyo-3d")!)
                    Text("路線形状・駅・停車パターン：Mini Tokyo 3D。原データ提供：公共交通オープンデータセンターおよび参加交通事業者。列車時刻は使用せず、停車パターンのみ照合します。")
                    Link("公共交通オープンデータ利用条件", destination: URL(string: "https://developer.odpt.org/terms")!)
                    Text("© 2019–2026 Akihiko Kusanagi / MIT License。同梱のライセンスに基づき利用。GPSの履歴はメモリ内で照合し、保存・送信しません。")
                    if let url = Bundle.main.url(forResource: "MiniTokyo3D-LICENSE", withExtension: "txt"), let license = try? String(contentsOf: url, encoding: .utf8) { Text(license).font(.caption2) }
                }
                Section("収録路線") {
                    ForEach(store.catalog?.lines ?? []) { line in
                        VStack(alignment: .leading) {
                            Text(line.name)
                            Text("\(line.stations.count)駅 / \(store.catalog?.patterns.filter { $0.line == line.id }.count ?? 0)停車パターン").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.navigationTitle("収録範囲・出典")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showCoverage = false } } }
        }
    }
}

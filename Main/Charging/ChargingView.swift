import SwiftUI
import Charts

struct ChargingView: View {
    var onHome: () -> Void
    @ObservedObject private var monitor = ChargingMonitor.shared
    @State private var showDiagnostics = false
    @State private var historyHours = 1
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        VStack(alignment: .leading, spacing: 12) {
                            Label(monitor.state.connected ? "電源に接続中" : "バッテリー使用中", systemImage: "bolt.fill")
                                .foregroundStyle(.green)
                            Text(monitor.state.powerText).font(.system(size: 52, weight: .medium, design: .rounded)).monospacedDigit()
                                .accessibilityIdentifier("charging-power")
                            Text(monitor.state.powerSource).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Label(monitor.state.percentText, systemImage: "battery.100percent")
                                Spacer()
                                Text(monitor.state.temperature.map { String(format: "%.1f °C", $0) } ?? "温度 取得不可")
                            }.font(.title3.monospacedDigit())
                            Text(monitor.state.charging ? "充電中" : "充電していません・保留状態は判別できない場合があります")
                                .font(.caption).foregroundStyle(.secondary)
                            if monitor.state.isStale(at: context.date) {
                                Label("更新停止・古い測定値", systemImage: "clock.badge.exclamationmark").foregroundStyle(.orange)
                            }
                            if monitor.state.date != .distantPast {
                                Text("測定: \(monitor.state.date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 12)
                    }
                }
                Section("充電完了予測・推定") {
                    prediction(80, eta: monitor.state.eta80)
                    prediction(100, eta: monitor.state.eta100)
                    Text("3分以上・2%以上の連続した充電履歴から計算します。高残量での速度低下と過去の履歴を考慮。充電上限・最適化充電・発熱による保留中は完了しない場合があります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("履歴") {
                    Picker("期間", selection: $historyHours) {
                        Text("1時間").tag(1); Text("6時間").tag(6); Text("24時間").tag(24)
                    }.pickerStyle(.segmented)
                    history("入力電力・実測由来", unit: "W", color: .green, value: { $0.watts })
                    history("バッテリー温度", unit: "°C", color: .orange, value: { $0.temperature })
                    history("残量", unit: "%", color: .blue, value: { $0.percent.map(Double.init) })
                    Text("欠測区間は線をつなぎません。履歴は端末内に最大7日間・12,000点保存します。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("動作設定") {
                    Toggle("充電を監視", isOn: Binding(get: { monitor.enabled }, set: { monitor.setEnabled($0) }))
                    Toggle("Live Activity", isOn: $monitor.liveEnabled)
                    if !monitor.activityMessage.isEmpty { Text(monitor.activityMessage).font(.caption).foregroundStyle(.orange) }
                    Text("前面では約2秒間隔。バックグラウンドではiOSにより停止します。Live Activityは20秒で古い値と表示し、停止を検出できた場合は直ちに表示します。接続・切断の自動処理はアプリが動作している間に限られます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("自動起動の設定") {
                    Text("ショートカット → オートメーション → 充電器 → 接続された → すぐに実行 → URLを開く: maincharge://start。切断時は maincharge://stop を開く設定を追加します。ロック解除が必要な場合があります。アプリからオートメーションを自動作成することはできません。")
                        .font(.footnote)
                    Button("取得状況・USB-C PD・診断") { showDiagnostics = true }
                    Text("iPhone 17e向け・iOS 26以降。センサー名の対応と実測精度は実機検証が必要です。ワイヤレス入力電流など、公開されない値は取得不可になります。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("充電モニター")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("ホーム", systemImage: "chevron.left", action: onHome).accessibilityLabel("ホームへ戻る")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("更新", systemImage: "arrow.clockwise") { Task { await monitor.read() } } }
            }
            .sheet(isPresented: $showDiagnostics) {
                NavigationStack {
                    ScrollView { Text(monitor.diagnostics).font(.caption.monospaced()).textSelection(.enabled).padding() }
                        .navigationTitle("取得診断")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showDiagnostics = false } }
                            ToolbarItem(placement: .bottomBar) { ShareLink(item: monitor.diagnostics) { Label("診断を共有", systemImage: "square.and.arrow.up") } }
                        }
                }
            }
        }
    }
    private func prediction(_ target: Int, eta: Date?) -> some View {
        HStack {
            Text("\(target)%")
            Spacer()
            if (monitor.state.percent ?? -1) >= target { Text("到達済み").foregroundStyle(.secondary) }
            else if let eta {
                VStack(alignment: .trailing) {
                    Text("約\(max(1, Int(eta.timeIntervalSince(monitor.state.date) / 60)))分")
                    Text(eta, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("履歴不足・予測不可").foregroundStyle(.secondary).font(.footnote) }
        }
    }
    private func history(_ title: String, unit: String, color: Color,
                         value: @escaping (ChargeSample) -> Double?) -> some View {
        let visible = monitor.samples.filter { Date().timeIntervalSince($0.date) < Double(historyHours) * 3600 }
        // Missing readings, suspension gaps and session changes each start a new line.
        var segment = 0
        var prior: ChargeSample?
        let points: [(ChargeSample, Int)] = visible.map { sample in
            if let p = prior, sample.session != p.session || sample.date.timeIntervalSince(p.date) > 30 || value(p) == nil { segment += 1 }
            prior = sample
            return (sample, segment)
        }
        return VStack(alignment: .leading) {
            Text("\(title) (\(unit))").font(.subheadline)
            if points.contains(where: { value($0.0) != nil }) {
                Chart {
                    ForEach(points, id: \.0.id) { sample, series in
                        if let number = value(sample) {
                            LineMark(x: .value("時刻", sample.date), y: .value(unit, number), series: .value("区間", series))
                                .foregroundStyle(color)
                        }
                    }
                }.frame(height: 100)
            } else { Text("取得できた履歴はありません").font(.caption).foregroundStyle(.secondary).frame(height: 64) }
        }.padding(.vertical, 6)
    }
}

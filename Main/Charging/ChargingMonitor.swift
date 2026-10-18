import SwiftUI
import UIKit
import ActivityKit
import WidgetKit

@MainActor final class ChargingMonitor: ObservableObject {
    static let shared = ChargingMonitor()
    @Published var state = ChargeState.empty
    @Published var samples: [ChargeSample] = []
    @Published var diagnostics = "センサーを確認中"
    @Published var activityMessage = ""
    @Published var enabled = true
    @Published private(set) var actualHertz = 0.0
    @Published private(set) var lastReadMilliseconds = 0.0
    @Published private(set) var backgroundReadCount = 0
    @Published var interval: Double = 0.1 {
        didSet { interval = max(0.1, interval); reconcileLoop() }
    }
    @Published var chartWindow: Double = 60 {
        didSet { rebuildChart(force: true) }
    }
    @Published var liveEnabled = UserDefaults.standard.object(forKey: "charging-live") as? Bool ?? true {
        didSet { UserDefaults.standard.set(liveEnabled, forKey: "charging-live"); Task { await publish(force: true) } }
    }
    private let probe = SensorProbe()
    private var loop: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var session = UUID()
    private var priorConnected: Bool?
    private var lastStored = Date.distantPast
    private var lastPublished = Date.distantPast
    private var lastWidget = Date.distantPast
    private var lastCache = Date.distantPast
    private var lastEstimate = Date.distantPast
    private var lastChart = Date.distantPast
    private var lastSampleDate: Date?
    private var archive: [ChargeSample] = []
    private var recent: [ChargeSample] = []
    private var chartArchive: [ChargeSample] = []
    private var estimate80: Date?
    private var estimate100: Date?
    private var active = false
    private var pipActive = false
    private var mayRead: Bool { enabled && (active || pipActive) }
    private var reading = false
    private var sequence = 0
    private lazy var diskStore = ChargingDiskStore(url: storeURL)
    private var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("charging-history.json")
    }
    init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([ChargeSample].self, from: data) { archive = saved }
        state = ChargingCache.load()
        UIDevice.current.isBatteryMonitoringEnabled = true
        for name in [UIDevice.batteryStateDidChangeNotification, UIDevice.batteryLevelDidChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.read() }
            })
        }
    }
    func setActive(_ value: Bool) {
        active = value
        reconcileLoop()
    }
    func setPiPActive(_ value: Bool) { pipActive = value; reconcileLoop() }
    private func reconcileLoop() {
        if mayRead {
            guard loop == nil else { return }
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    let started = ContinuousClock.now
                    await self?.read()
                    let delay = Duration.seconds(self?.interval ?? 0.1) - started.duration(to: .now)
                    do { try await Task.sleep(for: max(.milliseconds(1), delay)) }
                    catch { return }
                }
            }
        } else {
            if loop != nil { session = UUID() }
            loop?.cancel(); loop = nil
            state.paused = true; state.eta80 = nil; state.eta100 = nil
            estimate80 = nil; estimate100 = nil
            actualHertz = 0; lastSampleDate = nil
            persist()
            Task { await publish(force: true) }
        }
    }
    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { ChargingPiP.shared.stop() }
        reconcileLoop()
    }
    func read() async {
        guard mayRead, !reading else { return }
        reading = true
        defer { reading = false }
        let readStarted = ContinuousClock.now
        sequence += 1
        let result = await probe.read(lastExternalConnected: priorConnected, periodicRescan: false)
        guard mayRead else { return }
        let s = result.snapshot
        let battery = UIDevice.current
        let publicConnected = battery.batteryState == .charging || battery.batteryState == .full
        let connected = s.registry["ExternalConnected"] != nil || s.powerSource != nil ? s.externalConnected : publicConnected
        let disconnected = priorConnected == true && !connected
        if priorConnected != connected {
            session = UUID(); lastEstimate = .distantPast
            estimate80 = nil; estimate100 = nil
        }
        priorConnected = connected
        let level = battery.batteryLevel >= 0 ? Int((battery.batteryLevel * 100).rounded()) : s.percent
        let percent = level.flatMap { (0...100).contains($0) ? $0 : nil }
        let charging = connected && (battery.batteryState == .charging || s.isCharging)
        func sane(_ value: Double?) -> Double? {
            value.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        }
        let power = connected ? sane(s.inputWatts) : nil
        state = ChargeState(date: s.date, percent: percent, watts: power,
                            temperature: s.batteryTemperature, connected: connected, charging: charging,
                            paused: false, powerSource: power == nil ? "取得不可" : "実測由来・入力レール V×A（17e未校正）")
        if let previous = lastSampleDate {
            let delta = s.date.timeIntervalSince(previous)
            if delta > 0 {
                let instantaneous = min(100, 1 / delta)
                actualHertz = actualHertz == 0 ? instantaneous : actualHertz * 0.9 + instantaneous * 0.1
            }
        }
        lastSampleDate = s.date
        if !active && pipActive { backgroundReadCount += 1 }
        let sample = ChargeSample(date: s.date, session: session, percent: percent,
            watts: power, temperature: s.batteryTemperature, charging: charging)
        recent.append(sample)
        if recent.count > 1200 { recent.removeFirst(recent.count - 1200) }
        recent.removeAll { s.date.timeIntervalSince($0.date) > 120 }
        if s.date.timeIntervalSince(lastStored) >= 10 {
            lastStored = s.date
            archive.append(sample)
            archive = Array(archive.filter { s.date.timeIntervalSince($0.date) < 7 * 86400 }.suffix(12000))
            persist()
        }
        if s.date.timeIntervalSince(lastEstimate) >= 1 {
            lastEstimate = s.date
            if charging, let p = percent {
                estimate80 = ChargeEstimator.eta(target: 80, now: s.date, percent: p, session: session, samples: archive)
                estimate100 = ChargeEstimator.eta(target: 100, now: s.date, percent: p, session: session, samples: archive)
            } else { estimate80 = nil; estimate100 = nil }
        }
        state.eta80 = estimate80; state.eta100 = estimate100
        rebuildChart(force: false)
        ChargingPiP.shared.update(state, samples: recent, hertz: actualHertz)
        var system = utsname(); uname(&system)
        let machineSize = MemoryLayout.size(ofValue: system.machine)
        let model = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: machineSize) { String(cString: $0) }
        }
        var lines = ["端末: \(model) / iOS \(battery.systemVersion)",
            "iPhone 17e: センサー対応・精度は実機で未検証", "IOKit: \(probe.batteryAvailable) / HID: \(probe.hidAvailable) / services: \(result.serviceCount)",
            String(format: "設定 %.0f ms / 実取得 %.1f Hz / 前回処理 %.1f ms", interval * 1000, actualHertz, lastReadMilliseconds),
            "PiP: \(ChargingPiP.shared.status)",
            "PiP背景取得回数: \(backgroundReadCount)",
            "電力: \(state.powerSource)", "IOPSCopyChargeStatus結果: \(String(format: "0x%08x", result.chargeStatusError))（0xe00002c1 は権限拒否）", "セル電力: \(s.batteryWatts.map { String(format: "%.2f W", $0) } ?? "取得不可")",
            "温度: \(s.batteryTemperatureReadings.map(\.name).joined(separator: ", "))", "USB-PD（契約上限・実消費電力ではありません）"]
        if let profile = s.negotiatedProfile { lines.append("契約: \(profile.label) / 上限 \(profile.watts) W") }
        for profile in s.adapterProfiles { lines.append("PDO \(profile.index): \(profile.label)") }
        lines.append("レジストリ: \(s.registry)")
        lines.append("アダプター: \(s.adapterDetails ?? [:])")
        lines += s.sensors.map { "\($0.id): \($0.formatted)" }
        lines += s.temperatureWarnings
        if let partial = s.partialInputWatts { lines.append("入力矛盾を検出: \(partial) W を電力表示から除外") }
        diagnostics = lines.joined(separator: "\n")
        if s.date.timeIntervalSince(lastCache) >= 1 {
            lastCache = s.date
            ChargingCache.save(state)
        }
        await publish(force: false)
        let elapsed = readStarted.duration(to: .now).components
        lastReadMilliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        if disconnected { ChargingPiP.shared.stop() }
    }
    private func rebuildChart(force: Bool) {
        let now = state.date == .distantPast ? Date() : state.date
        if force || now.timeIntervalSince(lastChart) >= 1 {
            lastChart = now
            let cutoff = recent.first?.date ?? now
            chartArchive = ChargingHistory.chart(archive.filter {
                now.timeIntervalSince($0.date) <= chartWindow && $0.date < cutoff
            }, limit: 180)
        }
        let live = recent.filter { now.timeIntervalSince($0.date) <= chartWindow }
        samples = ChargingHistory.chart(chartArchive + live, limit: 360)
    }
    private func persist() {
        ChargingCache.save(state)
        let saved = archive
        let store = diskStore
        Task { await store.save(saved) }
    }
    private func publish(force: Bool) async {
        let activities = Activity<ChargingAttributes>.activities
        if !enabled || !liveEnabled || !state.connected {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard force || Date().timeIntervalSince(lastPublished) >= 1 else { return }
        lastPublished = Date()
        if Date().timeIntervalSince(lastWidget) >= 15 || force {
            lastWidget = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: "ChargingWidget")
        }
        let content = ActivityContent(state: state, staleDate: state.date.addingTimeInterval(20))
        if activities.isEmpty {
            guard active, ActivityAuthorizationInfo().areActivitiesEnabled else {
                activityMessage = "Live Activityが許可されていないか、アプリが停止中です"; return
            }
            do { _ = try Activity.request(attributes: ChargingAttributes(), content: content); activityMessage = "" }
            catch { activityMessage = "Live Activity: \(error.localizedDescription)" }
        } else {
            for activity in activities { await activity.update(content) }
        }
    }
}

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
    private var active = false
    private var reading = false
    private var sequence = 0
    private var storeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("charging-history.json")
    }
    init() {
        if let data = try? Data(contentsOf: storeURL),
           let saved = try? JSONDecoder().decode([ChargeSample].self, from: data) { samples = saved }
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
        loop?.cancel(); loop = nil
        if value && enabled {
            loop = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.read()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } else {
            state.paused = true; state.eta80 = nil; state.eta100 = nil
            persist()
            Task { await publish(force: true) }
        }
    }
    func setEnabled(_ value: Bool) { enabled = value; setActive(active) }
    func read() async {
        guard active, enabled, !reading else { return }
        reading = true
        defer { reading = false }
        sequence += 1
        let result = await probe.read(lastExternalConnected: priorConnected, periodicRescan: sequence % 15 == 0)
        guard active, enabled else { return }
        let s = result.snapshot
        let battery = UIDevice.current
        let publicConnected = battery.batteryState == .charging || battery.batteryState == .full
        let connected = s.registry["ExternalConnected"] != nil || s.powerSource != nil ? s.externalConnected : publicConnected
        if priorConnected != connected { session = UUID() }
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
        if s.date.timeIntervalSince(lastStored) >= 10 {
            lastStored = s.date
            samples.append(ChargeSample(date: s.date, session: session, percent: percent,
                watts: power, temperature: s.batteryTemperature, charging: charging))
            samples = Array(samples.filter { s.date.timeIntervalSince($0.date) < 7 * 86400 }.suffix(12000))
            persist()
        }
        if charging, let p = percent {
            state.eta80 = ChargeEstimator.eta(target: 80, now: s.date, percent: p, session: session, samples: samples)
            state.eta100 = ChargeEstimator.eta(target: 100, now: s.date, percent: p, session: session, samples: samples)
        }
        var system = utsname(); uname(&system)
        let machineSize = MemoryLayout.size(ofValue: system.machine)
        let model = withUnsafePointer(to: &system.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: machineSize) { String(cString: $0) }
        }
        var lines = ["端末: \(model) / iOS \(battery.systemVersion)",
            "iPhone 17e: センサー対応・精度は実機で未検証", "IOKit: \(probe.batteryAvailable) / HID: \(probe.hidAvailable) / services: \(result.serviceCount)",
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
        ChargingCache.save(state)
        await publish(force: false)
    }
    private func persist() {
        ChargingCache.save(state)
        try? FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(samples) { try? data.write(to: storeURL, options: .atomic) }
    }
    private func publish(force: Bool) async {
        let activities = Activity<ChargingAttributes>.activities
        if !enabled || !liveEnabled || !state.connected {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        guard force || Date().timeIntervalSince(lastPublished) >= 15 else { return }
        lastPublished = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: "ChargingWidget")
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

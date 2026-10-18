import SwiftUI
import WidgetKit
import ActivityKit

struct ChargingReadout: View {
    var state: ChargeState
    var stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("充電モニター", systemImage: "bolt.fill").foregroundStyle(.green)
                Spacer()
                Text(state.percentText)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.powerText).font(.title.bold()).monospacedDigit()
                Spacer()
                Text(state.temperature.map { String(format: "%.1f °C", $0) } ?? "温度 —").font(.caption)
            }
            Text(state.powerSource).font(.caption2).foregroundStyle(.secondary)
            if stale || state.paused {
                Label("更新停止・古い測定値", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
            } else {
                HStack {
                    eta("80%", date: state.eta80)
                    Spacer()
                    eta("100%", date: state.eta100)
                }.font(.caption)
            }
            HStack {
                Text("測定")
                Text(state.date, style: .time)
            }.font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func eta(_ label: String, date: Date?) -> some View {
        HStack(spacing: 3) {
            Text("\(label) 推定")
            if let date { Text(date, style: .time) } else { Text("—") }
        }
    }
}

struct ChargingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChargingAttributes.self) { context in
            ChargingReadout(state: context.state, stale: context.isStale)
                .padding().activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
                .widgetURL(URL(string: "maincharge://open"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    ChargingReadout(state: context.state, stale: context.isStale)
                }
            } compactLeading: {
                Image(systemName: context.isStale || context.state.paused ? "clock" : "bolt.fill").foregroundStyle(.green)
            } compactTrailing: {
                Text(context.isStale || context.state.paused ? "更新停止" : context.state.powerText).font(.caption2)
            } minimal: {
                Image(systemName: context.isStale || context.state.paused ? "clock" : "bolt.fill")
            }.widgetURL(URL(string: "maincharge://open"))
        }
    }
}

struct ChargeEntry: TimelineEntry { var date: Date; var state: ChargeState }
struct ChargeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChargeEntry { ChargeEntry(date: .now, state: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (ChargeEntry) -> Void) {
        completion(ChargeEntry(date: .now, state: ChargingCache.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ChargeEntry>) -> Void) {
        let state = ChargingCache.load()
        let now = Date()
        let expiry = max(now.addingTimeInterval(1), state.date.addingTimeInterval(21))
        completion(Timeline(entries: [ChargeEntry(date: now, state: state), ChargeEntry(date: expiry, state: state)],
                            policy: .after(now.addingTimeInterval(900))))
    }
}
struct ChargingHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChargingWidget", provider: ChargeProvider()) { entry in
            ChargingReadout(state: entry.state, stale: entry.state.isStale(at: entry.date))
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "maincharge://open"))
        }.configurationDisplayName("充電モニター").description("最後に取得した電力・残量と測定時刻")
            .supportedFamilies([.systemMedium])
    }
}
@main struct ChargingWidgets: WidgetBundle {
    var body: some Widget { ChargingLiveActivity(); ChargingHomeWidget() }
}

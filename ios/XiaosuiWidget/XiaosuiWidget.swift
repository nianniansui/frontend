import WidgetKit
import SwiftUI

/// 小碎 主屏 Widget
///
/// 设计原则：
/// 1. 单一目标 —— 让用户用最少的步骤说一句话；
/// 2. 不在 widget 里录音（系统不允许），而是打开 App 直接进录音态；
/// 3. 用 App Group 读最近 1 条记忆，让 widget "活着"，不只是个按钮。

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> XiaosuiEntry {
        XiaosuiEntry(date: Date(), latestSummary: "随口一记，随时找回")
    }

    func getSnapshot(in context: Context, completion: @escaping (XiaosuiEntry) -> ()) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<XiaosuiEntry>) -> ()) {
        // 1 小时刷新一次。Widget 主要是个入口，不是 dashboard
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> XiaosuiEntry {
        let groupId = "group.com.xiaosui.xiaosui"
        let defaults = UserDefaults(suiteName: groupId)
        let summary = defaults?.string(forKey: "latestSummary")
            ?? "按下 widget 直接说一句"
        return XiaosuiEntry(date: Date(), latestSummary: summary)
    }
}

struct XiaosuiEntry: TimelineEntry {
    let date: Date
    let latestSummary: String
}

struct XiaosuiWidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        // 整张 widget 都点击 → xiaosui://record
        Link(destination: URL(string: "xiaosui://record")!) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "mic.circle.fill")
                        .font(.title3)
                        .foregroundColor(Color(red: 0.91, green: 0.27, blue: 0.38))
                    Text("小碎")
                        .font(.headline)
                    Spacer()
                }
                Spacer(minLength: 0)
                Text(entry.latestSummary)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text("点这里说一句")
                    .font(.caption)
                    .foregroundColor(Color(red: 0.91, green: 0.27, blue: 0.38))
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

@main
struct XiaosuiWidget: Widget {
    let kind: String = "XiaosuiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            if #available(iOS 17.0, *) {
                XiaosuiWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                XiaosuiWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("小碎")
        .description("一键开始录音，最近一条记忆始终在屏。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

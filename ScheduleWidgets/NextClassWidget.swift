import WidgetKit
import SwiftUI

struct NextClassEntry: TimelineEntry {
    let date: Date
    let card: WidgetSnapshot.WidgetClassCard?
}

struct NextClassProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextClassEntry {
        NextClassEntry(date: Date(), card: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextClassEntry) -> Void) {
        completion(NextClassEntry(date: Date(), card: WidgetDataReader.snapshot().nextClass ?? sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextClassEntry>) -> Void) {
        let snap = WidgetDataReader.snapshot()
        let entry = NextClassEntry(date: Date(), card: snap.nextClass)
        let next = Calendar.kege.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var sample: WidgetSnapshot.WidgetClassCard {
        .init(
            id: UUID(),
            title: "艺术学理论",
            teacher: "示例",
            location: "教学楼 A201",
            weekdayLabel: "周一",
            timeRangeLabel: "08:00–09:40",
            startMinutes: 480,
            endMinutes: 580
        )
    }
}

struct NextClassWidgetView: View {
    var entry: NextClassEntry

    var body: some View {
        if let card = entry.card {
            VStack(alignment: .leading, spacing: 6) {
                Text("下一节")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.70, green: 0.23, blue: 0.23))
                Text(card.title)
                    .font(.headline)
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                Text(card.timeRangeLabel)
                    .font(.subheadline.monospacedDigit())
                if !card.location.isEmpty {
                    Text(card.location)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("课格")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading) {
                Text("课格")
                    .font(.caption.weight(.semibold))
                Text("暂无下一节课")
                    .font(.headline)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KegeNextClass", provider: NextClassProvider()) { entry in
            if #available(iOS 17.0, *) {
                NextClassWidgetView(entry: entry)
                    .containerBackground(Color(red: 0.965, green: 0.945, blue: 0.910), for: .widget)
            } else {
                NextClassWidgetView(entry: entry)
                    .padding()
                    .background(Color(red: 0.965, green: 0.945, blue: 0.910))
            }
        }
        .configurationDisplayName("下一节课")
        .description("主屏幕小尺寸：下一节课的名称、时间与地点。")
        .supportedFamilies([.systemSmall])
    }
}

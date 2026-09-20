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
            location: "6406",
            weekdayLabel: "周一",
            timeRangeLabel: "09:00–12:00",
            startMinutes: 540,
            endMinutes: 720
        )
    }
}

struct NextClassWidgetView: View {
    var entry: NextClassEntry

    var body: some View {
        if let card = entry.card {
            VStack(alignment: .leading, spacing: 0) {
                Text("下一节")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetLook.muted)
                Spacer(minLength: 8)
                Text(card.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(WidgetLook.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 10)
                Text(card.clockRange)
                    .font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetLook.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !card.location.isEmpty {
                    Spacer(minLength: 6)
                    Text(card.location)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(WidgetLook.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("下一节 \(card.title) \(card.clockRange) \(card.location)")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("下一节")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetLook.muted)
                Spacer(minLength: 0)
                Text("这会儿没有课")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(WidgetLook.ink)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

struct NextClassWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KegeNextClass", provider: NextClassProvider()) { entry in
            if #available(iOS 17.0, *) {
                NextClassWidgetView(entry: entry)
                    .containerBackground(WidgetLook.paper, for: .widget)
            } else {
                NextClassWidgetView(entry: entry)
                    .padding()
                    .background(WidgetLook.paper)
            }
        }
        .configurationDisplayName("下一节课")
        .description("课名、上下课时间、教室。不用打开应用。")
        .supportedFamilies([.systemSmall])
    }
}

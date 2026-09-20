import WidgetKit
import SwiftUI

struct RemainingTodayEntry: TimelineEntry {
    let date: Date
    let cards: [WidgetSnapshot.WidgetClassCard]
}

struct RemainingTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemainingTodayEntry {
        RemainingTodayEntry(date: Date(), cards: [sample, sample2])
    }

    func getSnapshot(in context: Context, completion: @escaping (RemainingTodayEntry) -> Void) {
        let cards = WidgetDataReader.snapshot().remainingToday
        completion(RemainingTodayEntry(date: Date(), cards: cards.isEmpty ? [sample] : cards))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RemainingTodayEntry>) -> Void) {
        let cards = WidgetDataReader.snapshot().remainingToday
        let entry = RemainingTodayEntry(date: Date(), cards: cards)
        let next = Calendar.kege.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private var sample: WidgetSnapshot.WidgetClassCard {
        .init(
            id: UUID(),
            title: "艺术学理论",
            teacher: "",
            location: "6406",
            weekdayLabel: "周一",
            timeRangeLabel: "09:00–12:00",
            startMinutes: 540,
            endMinutes: 720
        )
    }

    private var sample2: WidgetSnapshot.WidgetClassCard {
        .init(
            id: UUID(),
            title: "作品研讨",
            teacher: "",
            location: "工作室",
            weekdayLabel: "周一",
            timeRangeLabel: "14:00–15:40",
            startMinutes: 840,
            endMinutes: 940
        )
    }
}

struct RemainingTodayWidgetView: View {
    var entry: RemainingTodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WidgetLook.muted)
            if entry.cards.isEmpty {
                Spacer(minLength: 12)
                Text("今天没有课")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(WidgetLook.ink)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entry.cards.prefix(5)) { card in
                        Text(card.remainingLine)
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(WidgetLook.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .accessibilityLabel(card.remainingLine)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: String {
        if entry.cards.isEmpty { return "今日剩余" }
        return "今日剩余 \(entry.cards.count) 节"
    }
}

struct RemainingTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KegeRemainingToday", provider: RemainingTodayProvider()) { entry in
            if #available(iOS 17.0, *) {
                RemainingTodayWidgetView(entry: entry)
                    .containerBackground(WidgetLook.paper, for: .widget)
            } else {
                RemainingTodayWidgetView(entry: entry)
                    .padding()
                    .background(WidgetLook.paper)
            }
        }
        .configurationDisplayName("今日剩余课程")
        .description("一行一眼：时间、教室、课名。")
        .supportedFamilies([.systemMedium])
    }
}

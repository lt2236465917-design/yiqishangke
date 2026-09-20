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
        .init(id: UUID(), title: "艺术学理论", teacher: "", location: "A201", weekdayLabel: "周一", timeRangeLabel: "08:00–09:40", startMinutes: 480, endMinutes: 580)
    }

    private var sample2: WidgetSnapshot.WidgetClassCard {
        .init(id: UUID(), title: "作品研讨", teacher: "", location: "工作室", weekdayLabel: "周一", timeRangeLabel: "14:00–15:40", startMinutes: 840, endMinutes: 940)
    }
}

struct RemainingTodayWidgetView: View {
    var entry: RemainingTodayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日剩余")
                    .font(.headline)
                Spacer()
                Text("课格")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if entry.cards.isEmpty {
                Spacer()
                Text("今天没有剩余课程")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(entry.cards.prefix(4)) { card in
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.timeRangeLabel)
                            .font(.caption.monospacedDigit())
                            .frame(width: 84, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(card.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if !card.location.isEmpty {
                                Text(card.location)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

struct RemainingTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KegeRemainingToday", provider: RemainingTodayProvider()) { entry in
            if #available(iOS 17.0, *) {
                RemainingTodayWidgetView(entry: entry)
                    .containerBackground(Color(red: 0.965, green: 0.945, blue: 0.910), for: .widget)
            } else {
                RemainingTodayWidgetView(entry: entry)
                    .padding()
                    .background(Color(red: 0.965, green: 0.945, blue: 0.910))
            }
        }
        .configurationDisplayName("今日剩余课程")
        .description("主屏幕中尺寸：今天还未上完的课。")
        .supportedFamilies([.systemMedium])
    }
}

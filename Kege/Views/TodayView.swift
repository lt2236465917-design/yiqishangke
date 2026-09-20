import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @EnvironmentObject private var sync: SyncCoordinator
    @EnvironmentObject private var settings: SettingsStore

    private var today: [ClassSession] {
        ScheduleQuery.sessions(on: Date(), in: schedule.sessions)
    }

    private var current: ClassSession? {
        ScheduleQuery.currentClass(in: schedule.sessions)
    }

    private var next: ClassSession? {
        ScheduleQuery.nextClass(in: schedule.sessions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if today.isEmpty {
                        EmptyStateView(
                            title: "今天没有课",
                            detail: "从学校门户同步，或导入课表截图。门户课表地址尚未核实，截图是可用的备用路径。",
                            systemImage: "cup.and.saucer"
                        )
                    } else {
                        if let current {
                            KegeCard {
                                Text("正在上课")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(KegeTheme.accent)
                                ClassRowView(session: current, emphasize: true)
                            }
                        }
                        if let next, next.id != current?.id, next.weekday == ChinaWeekday.from(date: Date()) {
                            KegeCard {
                                Text("下一节")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(KegeTheme.sage)
                                ClassRowView(session: next)
                            }
                        }
                        KegeCard {
                            Text("今日全部")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(today) { session in
                                ClassRowView(session: session, emphasize: session.id == current?.id)
                                if session.id != today.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(KegeTheme.paper.ignoresSafeArea())
            .navigationTitle("课格")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sync.beginManualSync()
                    } label: {
                        Label("同步课表", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Self.dateLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("一起上课")
                .font(KegeTheme.displayFont)
                .foregroundStyle(KegeTheme.ink)
            if let last = settings.lastSyncAt {
                Text("上次更新 \(Self.timeFormatter.string(from: last)) · \(settings.lastSyncNote)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private static var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: Date())
    }

    private static var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }
}

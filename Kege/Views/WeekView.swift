import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var schedule: ScheduleStore
    @State private var selectedDay = Date()

    private var days: [Date] { ScheduleQuery.weekDays(containing: Date()) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                weekStrip
                let selectedSessions = ScheduleQuery.sessions(on: selectedDay, in: schedule.sessions)
                if selectedSessions.isEmpty {
                    EmptyStateView(
                        title: "这天没有课",
                        detail: "左右切换星期，或去导入截图。",
                        systemImage: "calendar"
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(selectedSessions) { session in
                                ClassRowView(session: session)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                Divider().padding(.leading, 92)
                            }
                        }
                        .background(KegeTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(20)
                    }
                }
            }
            .background(KegeTheme.paper.ignoresSafeArea())
            .navigationTitle("本周")
        }
    }

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(days, id: \.self) { day in
                let weekday = ChinaWeekday.from(date: day)
                let count = ScheduleQuery.sessions(on: day, in: schedule.sessions).count
                let selected = Calendar.kege.isDate(day, inSameDayAs: selectedDay)
                Button {
                    selectedDay = day
                } label: {
                    VStack(spacing: 6) {
                        Text(weekday.shortLabel.replacingOccurrences(of: "周", with: ""))
                            .font(.caption.weight(.semibold))
                        Text(dayNumber(day))
                            .font(.headline.monospacedDigit())
                        Circle()
                            .fill(count == 0 ? Color.clear : KegeTheme.accent)
                            .frame(width: 6, height: 6)
                    }
                    .foregroundStyle(selected ? Color.white : KegeTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? KegeTheme.accent : KegeTheme.card)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func dayNumber(_ date: Date) -> String {
        String(Calendar.kege.component(.day, from: date))
    }
}

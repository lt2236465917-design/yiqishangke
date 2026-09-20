import Foundation
import Combine
import WidgetKit

@MainActor
final class ScheduleStore: ObservableObject {
    @Published private(set) var timetable: Timetable
    @Published var usingAppGroupFallback = false

    init() {
        usingAppGroupFallback = !AppGroup.isAppGroupAvailable
        timetable = Self.loadFromDisk() ?? Timetable(sessions: [], lastUpdated: nil, lastSource: nil, portalNote: nil)
        writeWidgetSnapshot()
    }

    var sessions: [ClassSession] { timetable.sessions }

    func replaceAll(_ sessions: [ClassSession], source: ClassSource, note: String? = nil) {
        timetable = Timetable(
            sessions: Self.sorted(sessions),
            lastUpdated: Date(),
            lastSource: source,
            portalNote: note
        )
        persist()
    }

    func merge(_ incoming: [ClassSession], source: ClassSource, note: String? = nil) {
        var map = Dictionary(uniqueKeysWithValues: timetable.sessions.map { ($0.identityKey, $0) })
        for item in incoming {
            map[item.identityKey] = item
        }
        timetable = Timetable(
            sessions: Self.sorted(Array(map.values)),
            lastUpdated: Date(),
            lastSource: source,
            portalNote: note
        )
        persist()
    }

    func clear() {
        timetable = Timetable(sessions: [], lastUpdated: Date(), lastSource: nil, portalNote: "已清空本机课表")
        persist()
    }

    func persist() {
        do {
            try FileManager.default.createDirectory(at: AppGroup.containerURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.kege.encode(timetable)
            try data.write(to: AppGroup.scheduleURL, options: [.atomic])
            writeWidgetSnapshot()
            WidgetCenter.shared.reloadAllTimelines()
            SafeLog.info("Schedule persisted (\(timetable.sessions.count) classes)")
        } catch {
            SafeLog.error("Schedule persist failed: \(error.localizedDescription)")
        }
    }

    func writeWidgetSnapshot() {
        let now = Date()
        let remaining = ScheduleQuery.remainingToday(now: now, in: timetable.sessions)
        let next = ScheduleQuery.nextClass(now: now, in: timetable.sessions)
        let snapshot = WidgetSnapshot(
            generatedAt: now,
            nextClass: next.map(Self.card),
            remainingToday: remaining.map(Self.card)
        )
        do {
            try FileManager.default.createDirectory(at: AppGroup.containerURL, withIntermediateDirectories: true)
            let data = try JSONEncoder.kege.encode(snapshot)
            try data.write(to: AppGroup.widgetSnapshotURL, options: [.atomic])
        } catch {
            SafeLog.error("Widget snapshot write failed: \(error.localizedDescription)")
        }
    }

    private static func loadFromDisk() -> Timetable? {
        guard let data = try? Data(contentsOf: AppGroup.scheduleURL) else { return nil }
        return try? JSONDecoder.kege.decode(Timetable.self, from: data)
    }

    private static func sorted(_ sessions: [ClassSession]) -> [ClassSession] {
        sessions.sorted { lhs, rhs in
            if lhs.weekday.rawValue != rhs.weekday.rawValue {
                return lhs.weekday.rawValue < rhs.weekday.rawValue
            }
            return lhs.startMinutes < rhs.startMinutes
        }
    }

    private static func card(_ session: ClassSession) -> WidgetSnapshot.WidgetClassCard {
        WidgetSnapshot.WidgetClassCard(
            id: session.id,
            title: session.title,
            teacher: session.teacher,
            location: session.location,
            weekdayLabel: session.weekday.shortLabel,
            timeRangeLabel: session.timeRangeLabel,
            startMinutes: session.startMinutes,
            endMinutes: session.endMinutes
        )
    }
}

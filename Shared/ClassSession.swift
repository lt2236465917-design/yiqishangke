import Foundation

enum ClassSource: String, Codable, Sendable {
    case portal
    case screenshot
    case manual
}

struct ClassSession: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var title: String
    var teacher: String
    var location: String
    var weekday: ChinaWeekday
    /// Minutes from 00:00 local time.
    var startMinutes: Int
    var endMinutes: Int
    /// Academic weeks this class meets. `nil` means every week.
    var weeks: [Int]?
    var termStart: Date?
    var notes: String
    var source: ClassSource
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        teacher: String = "",
        location: String = "",
        weekday: ChinaWeekday,
        startMinutes: Int,
        endMinutes: Int,
        weeks: [Int]? = nil,
        termStart: Date? = nil,
        notes: String = "",
        source: ClassSource,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.teacher = teacher
        self.location = location
        self.weekday = weekday
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.weeks = weeks
        self.termStart = termStart
        self.notes = notes
        self.source = source
        self.updatedAt = updatedAt
    }

    var startTimeLabel: String { Self.clockLabel(startMinutes) }
    var endTimeLabel: String { Self.clockLabel(endMinutes) }
    var timeRangeLabel: String { "\(startTimeLabel)–\(endTimeLabel)" }

    var durationMinutes: Int { max(0, endMinutes - startMinutes) }

    func occurs(on date: Date, calendar: Calendar = .kege) -> Bool {
        guard ChinaWeekday.from(date: date, calendar: calendar) == weekday else { return false }
        guard let weeks, let termStart else { return true }
        let weekIndex = Self.academicWeek(for: date, termStart: termStart, calendar: calendar)
        return weeks.contains(weekIndex)
    }

    func startDate(on day: Date, calendar: Calendar = .kege) -> Date? {
        Self.date(on: day, minutes: startMinutes, calendar: calendar)
    }

    func endDate(on day: Date, calendar: Calendar = .kege) -> Date? {
        Self.date(on: day, minutes: endMinutes, calendar: calendar)
    }

    var identityKey: String {
        let weekKey = (weeks ?? []).map(String.init).joined(separator: ",")
        return "\(title)|\(weekday.rawValue)|\(startMinutes)|\(endMinutes)|\(location)|\(weekKey)"
    }

    static func clockLabel(_ minutes: Int) -> String {
        let clamped = max(0, min(minutes, 24 * 60 - 1))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    static func minutes(hour: Int, minute: Int) -> Int {
        hour * 60 + minute
    }

    static func date(on day: Date, minutes: Int, calendar: Calendar = .kege) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        comps.second = 0
        return calendar.date(from: comps)
    }

    static func academicWeek(for date: Date, termStart: Date, calendar: Calendar = .kege) -> Int {
        let start = calendar.startOfDay(for: termStart)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return max(1, days / 7 + 1)
    }
}

struct Timetable: Codable, Sendable {
    var sessions: [ClassSession]
    var lastUpdated: Date?
    var lastSource: ClassSource?
    var portalNote: String?
}

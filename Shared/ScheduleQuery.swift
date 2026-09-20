import Foundation

enum ScheduleQuery {
    static func sessions(on date: Date, in sessions: [ClassSession], calendar: Calendar = .kege) -> [ClassSession] {
        sessions
            .filter { $0.occurs(on: date, calendar: calendar) }
            .sorted { $0.startMinutes < $1.startMinutes }
    }

    static func remainingToday(now: Date = Date(), in sessions: [ClassSession], calendar: Calendar = .kege) -> [ClassSession] {
        let minutes = currentMinutes(now: now, calendar: calendar)
        return sessions(on: now, in: sessions, calendar: calendar)
            .filter { $0.endMinutes > minutes }
    }

    static func nextClass(now: Date = Date(), in sessions: [ClassSession], calendar: Calendar = .kege) -> ClassSession? {
        let minutes = currentMinutes(now: now, calendar: calendar)
        if let laterToday = sessions(on: now, in: sessions, calendar: calendar)
            .first(where: { $0.startMinutes > minutes }) {
            return laterToday
        }
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            if let first = sessions(on: day, in: sessions, calendar: calendar).first {
                return first
            }
        }
        return nil
    }

    static func currentClass(now: Date = Date(), in sessions: [ClassSession], calendar: Calendar = .kege) -> ClassSession? {
        let minutes = currentMinutes(now: now, calendar: calendar)
        return sessions(on: now, in: sessions, calendar: calendar)
            .first { $0.startMinutes <= minutes && minutes < $0.endMinutes }
    }

    static func currentMinutes(now: Date = Date(), calendar: Calendar = .kege) -> Int {
        let h = calendar.component(.hour, from: now)
        let m = calendar.component(.minute, from: now)
        return h * 60 + m
    }

    static func weekDays(containing date: Date, calendar: Calendar = .kege) -> [Date] {
        let weekday = ChinaWeekday.from(date: date, calendar: calendar)
        let mondayOffset = 1 - weekday.rawValue
        guard let monday = calendar.date(byAdding: .day, value: mondayOffset, to: calendar.startOfDay(for: date)) else {
            return []
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }
}

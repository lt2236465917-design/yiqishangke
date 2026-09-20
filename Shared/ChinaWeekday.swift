import Foundation

/// China weekday: Monday = 1 … Sunday = 7.
/// Apple `DateComponents.weekday`: Sunday = 1 … Saturday = 7.
enum ChinaWeekday: Int, Codable, CaseIterable, Identifiable, Sendable {
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6
    case sunday = 7

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        case .sunday: "周日"
        }
    }

    var fullLabel: String {
        switch self {
        case .monday: "星期一"
        case .tuesday: "星期二"
        case .wednesday: "星期三"
        case .thursday: "星期四"
        case .friday: "星期五"
        case .saturday: "星期六"
        case .sunday: "星期日"
        }
    }

    /// `DateComponents.weekday` value used by UserNotifications / Calendar.
    var appleWeekday: Int {
        switch self {
        case .sunday: 1
        default: rawValue + 1
        }
    }

    static func from(date: Date, calendar: Calendar = .kege) -> ChinaWeekday {
        let apple = calendar.component(.weekday, from: date)
        let china = apple == 1 ? 7 : apple - 1
        return ChinaWeekday(rawValue: china) ?? .monday
    }

    static func parse(from text: String) -> ChinaWeekday? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let map: [String: ChinaWeekday] = [
            "1": .monday, "一": .monday, "周一": .monday, "星期一": .monday, "Monday": .monday, "Mon": .monday,
            "2": .tuesday, "二": .tuesday, "周二": .tuesday, "星期二": .tuesday, "Tuesday": .tuesday, "Tue": .tuesday,
            "3": .wednesday, "三": .wednesday, "周三": .wednesday, "星期三": .wednesday, "Wednesday": .wednesday, "Wed": .wednesday,
            "4": .thursday, "四": .thursday, "周四": .thursday, "星期四": .thursday, "Thursday": .thursday, "Thu": .thursday,
            "5": .friday, "五": .friday, "周五": .friday, "星期五": .friday, "Friday": .friday, "Fri": .friday,
            "6": .saturday, "六": .saturday, "周六": .saturday, "星期六": .saturday, "Saturday": .saturday, "Sat": .saturday,
            "7": .sunday, "日": .sunday, "天": .sunday, "周日": .sunday, "周天": .sunday,
            "星期日": .sunday, "星期天": .sunday, "Sunday": .sunday, "Sun": .sunday
        ]
        if let exact = map[t] { return exact }
        for (key, value) in map where key.count > 1 && t.contains(key) {
            return value
        }
        return nil
    }
}

extension Calendar {
    static var kege: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        cal.timeZone = .current
        cal.firstWeekday = 2
        return cal
    }
}

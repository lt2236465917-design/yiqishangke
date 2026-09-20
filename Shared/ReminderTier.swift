import Foundation

/// Three independent reminder offsets (r4). Multiple tiers may be enabled at once.
enum ReminderTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case minutes15
    case hours3
    case day1

    var id: String { rawValue }

    var offset: TimeInterval {
        switch self {
        case .minutes15: 15 * 60
        case .hours3: 3 * 60 * 60
        case .day1: 24 * 60 * 60
        }
    }

    var title: String {
        switch self {
        case .minutes15: "提前 15 分钟"
        case .hours3: "提前 3 小时"
        case .day1: "提前 1 天"
        }
    }

    var shortTitle: String {
        switch self {
        case .minutes15: "15 分钟"
        case .hours3: "3 小时"
        case .day1: "1 天"
        }
    }

    var subtitle: String {
        switch self {
        case .minutes15: "出门前再看一眼教室与课程"
        case .hours3: "给路程和准备留出余量"
        case .day1: "前一晚确认明天课表"
        }
    }

    var systemImage: String {
        switch self {
        case .minutes15: "bell.badge"
        case .hours3: "clock.badge"
        case .day1: "calendar.badge.clock"
        }
    }

    var notificationIdSuffix: String {
        rawValue
    }

    var leadCopy: String {
        switch self {
        case .minutes15: "15 分钟后上课"
        case .hours3: "3 小时后上课"
        case .day1: "明天有课"
        }
    }
}

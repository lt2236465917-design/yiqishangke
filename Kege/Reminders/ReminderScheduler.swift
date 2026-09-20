import Foundation
import UserNotifications
import ObjectiveC

@MainActor
final class ReminderScheduler {
    static let shared = ReminderScheduler()
    private let center = UNUserNotificationCenter.current()
    private let prefix = "kege.class."
    private let maxPending = 60

    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                SafeLog.error("Notification auth failed: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Rebuild every notification from the current timetable and enabled tiers. Past fire dates are skipped.
    func rebuild(sessions: [ClassSession], enabledTiers: [ReminderTier], now: Date = Date()) async {
        await removeAllKegeNotifications()
        guard !enabledTiers.isEmpty, !sessions.isEmpty else {
            SafeLog.info("Reminders rebuilt: none (tiers=\(enabledTiers.count), classes=\(sessions.count))")
            return
        }

        let horizon = Calendar.kege.date(byAdding: .day, value: 21, to: now) ?? now.addingTimeInterval(21 * 24 * 3600)
        var requests: [UNNotificationRequest] = []

        for session in sessions {
            for tier in enabledTiers {
                requests.append(contentsOf: makeRequests(session: session, tier: tier, now: now, horizon: horizon))
            }
        }

        let ranked = requests.sorted { lhs, rhs in
            (lhs.triggerDate ?? .distantFuture) < (rhs.triggerDate ?? .distantFuture)
        }
        let capped = Array(ranked.prefix(maxPending))
        for request in capped {
            do {
                try await center.add(request)
            } catch {
                SafeLog.error("Failed to schedule reminder \(request.identifier): \(error.localizedDescription)")
            }
        }
        SafeLog.info("Reminders rebuilt: scheduled \(capped.count) / generated \(requests.count)")
    }

    private func removeAllKegeNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func makeRequests(
        session: ClassSession,
        tier: ReminderTier,
        now: Date,
        horizon: Date
    ) -> [UNNotificationRequest] {
        var result: [UNNotificationRequest] = []
        let calendar = Calendar.kege

        if let weeks = session.weeks, let termStart = session.termStart, !weeks.isEmpty {
            for week in weeks {
                let days = (week - 1) * 7 + (session.weekday.rawValue - 1)
                guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: termStart)),
                      let start = session.startDate(on: day, calendar: calendar) else { continue }
                if let request = request(session: session, tier: tier, fireFromClassStart: start, now: now, horizon: horizon, repeats: false) {
                    result.append(request)
                }
            }
        } else {
            guard let todayStart = session.startDate(on: now, calendar: calendar) else { return [] }
            let weekdayDelta = session.weekday.rawValue - ChinaWeekday.from(date: now, calendar: calendar).rawValue
            let offsetDays = weekdayDelta >= 0 ? weekdayDelta : weekdayDelta + 7
            let firstOccurrence = todayStart.addingTimeInterval(TimeInterval(offsetDays * 24 * 3600))
            let adjusted = firstOccurrence < now && offsetDays == 0
                ? firstOccurrence.addingTimeInterval(7 * 24 * 3600)
                : firstOccurrence
            if let request = request(session: session, tier: tier, fireFromClassStart: adjusted, now: now, horizon: horizon, repeats: true) {
                result.append(request)
            }
        }
        return result
    }

    private func request(
        session: ClassSession,
        tier: ReminderTier,
        fireFromClassStart start: Date,
        now: Date,
        horizon: Date,
        repeats: Bool
    ) -> UNNotificationRequest? {
        let fire = start.addingTimeInterval(-tier.offset)
        guard fire > now else { return nil }
        if !repeats && fire > horizon { return nil }

        let content = UNMutableNotificationContent()
        content.title = "课格 · \(tier.leadCopy)"
        content.body = body(for: session)
        content.sound = .default
        content.threadIdentifier = "kege.schedule"

        let calendar = Calendar.kege
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger: UNNotificationTrigger
        if repeats {
            var weekly = DateComponents()
            weekly.weekday = calendar.dateComponents([.weekday], from: fire).weekday
            weekly.hour = comps.hour
            weekly.minute = comps.minute
            trigger = UNCalendarNotificationTrigger(dateMatching: weekly, repeats: true)
        } else {
            trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        }

        let identifier = "\(prefix)\(session.id.uuidString).\(tier.notificationIdSuffix).\(repeats ? "w" : stamp(fire))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        request.kegeFireDate = fire
        return request
    }

    private func body(for session: ClassSession) -> String {
        var parts = [session.title]
        if !session.location.isEmpty { parts.append(session.location) }
        if !session.teacher.isEmpty { parts.append(session.teacher) }
        parts.append(session.timeRangeLabel)
        return parts.joined(separator: " · ")
    }

    private func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date)
    }
}

private var kegeFireDateKey: UInt8 = 0

private extension UNNotificationRequest {
    var kegeFireDate: Date? {
        get { objc_getAssociatedObject(self, &kegeFireDateKey) as? Date }
        set { objc_setAssociatedObject(self, &kegeFireDateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var triggerDate: Date? { kegeFireDate }
}

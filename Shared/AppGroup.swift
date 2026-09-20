import Foundation

/// App Group used by 课格 and ScheduleWidgets to share the on-device timetable store.
enum AppGroup {
    static let identifier = "group.cn.yiqishangke.Kege"

    static let scheduleFileName = "schedule.json"
    static let widgetSnapshotFileName = "widget-snapshot.json"
    static let settingsSuiteName = identifier

    /// Shared container, or Application Support fallback if the App Group is not yet provisioned.
    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        let fallback = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KegeLocal", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var scheduleURL: URL {
        containerURL.appendingPathComponent(scheduleFileName)
    }

    static var widgetSnapshotURL: URL {
        containerURL.appendingPathComponent(widgetSnapshotFileName)
    }

    static var isAppGroupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
}

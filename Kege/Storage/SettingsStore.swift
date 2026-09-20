import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    @Published var reminderMinutes15: Bool {
        didSet { defaults.set(reminderMinutes15, forKey: Keys.m15) }
    }
    @Published var reminderHours3: Bool {
        didSet { defaults.set(reminderHours3, forKey: Keys.h3) }
    }
    @Published var reminderDay1: Bool {
        didSet { defaults.set(reminderDay1, forKey: Keys.d1) }
    }
    @Published var lastSyncAt: Date? {
        didSet { defaults.set(lastSyncAt, forKey: Keys.lastSync) }
    }
    @Published var lastSyncNote: String {
        didSet { defaults.set(lastSyncNote, forKey: Keys.lastSyncNote) }
    }
    @Published var replaceOnImport: Bool {
        didSet { defaults.set(replaceOnImport, forKey: Keys.replaceOnImport) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: AppGroup.settingsSuiteName) ?? .standard) {
        self.defaults = defaults
        self.reminderMinutes15 = defaults.bool(forKey: Keys.m15)
        self.reminderHours3 = defaults.bool(forKey: Keys.h3)
        self.reminderDay1 = defaults.bool(forKey: Keys.d1)
        self.lastSyncAt = defaults.object(forKey: Keys.lastSync) as? Date
        self.lastSyncNote = defaults.string(forKey: Keys.lastSyncNote) ?? ""
        self.replaceOnImport = defaults.object(forKey: Keys.replaceOnImport) as? Bool ?? true
    }

    var enabledTiers: [ReminderTier] {
        var tiers: [ReminderTier] = []
        if reminderMinutes15 { tiers.append(.minutes15) }
        if reminderHours3 { tiers.append(.hours3) }
        if reminderDay1 { tiers.append(.day1) }
        return tiers
    }

    func isEnabled(_ tier: ReminderTier) -> Bool {
        switch tier {
        case .minutes15: reminderMinutes15
        case .hours3: reminderHours3
        case .day1: reminderDay1
        }
    }

    func set(_ tier: ReminderTier, enabled: Bool) {
        switch tier {
        case .minutes15: reminderMinutes15 = enabled
        case .hours3: reminderHours3 = enabled
        case .day1: reminderDay1 = enabled
        }
    }

    private enum Keys {
        static let m15 = "reminder.minutes15"
        static let h3 = "reminder.hours3"
        static let d1 = "reminder.day1"
        static let lastSync = "sync.lastAt"
        static let lastSyncNote = "sync.lastNote"
        static let replaceOnImport = "import.replace"
    }
}

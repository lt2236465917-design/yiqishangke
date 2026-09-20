import Foundation
import Combine

@MainActor
final class SyncCoordinator: ObservableObject {
    @Published var isPresentingLogin = false
    @Published var lastError: String?
    @Published var lastMessage: String?

    let credentialsStore: CredentialsStore
    let scheduleStore: ScheduleStore
    let settingsStore: SettingsStore
    let reminderScheduler: ReminderScheduler
    let loginSession: LoginWebViewSession

    init(
        credentialsStore: CredentialsStore = .shared,
        scheduleStore: ScheduleStore,
        settingsStore: SettingsStore,
        reminderScheduler: ReminderScheduler? = nil,
        loginSession: LoginWebViewSession? = nil
    ) {
        self.credentialsStore = credentialsStore
        self.scheduleStore = scheduleStore
        self.settingsStore = settingsStore
        self.reminderScheduler = reminderScheduler ?? .shared
        self.loginSession = loginSession ?? LoginWebViewSession()
    }

    func beginManualSync() {
        do {
            guard let credentials = try credentialsStore.loadSchoolCredentials(), credentials.isComplete else {
                lastError = "请先在设置中保存学号和密码（仅本机钥匙串）。"
                return
            }
            lastError = nil
            loginSession.start(credentials: credentials)
            isPresentingLogin = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func applyParseResult(_ result: ParseResult, replace: Bool = true) async {
        let sessions = result.classes.compactMap { $0.asSession(source: .portal) }
        if sessions.isEmpty {
            lastError = result.blocker ?? "解析结果为空。"
            return
        }
        if replace {
            scheduleStore.replaceAll(sessions, source: .portal, note: result.sourceDescription)
        } else {
            scheduleStore.merge(sessions, source: .portal, note: result.sourceDescription)
        }
        settingsStore.lastSyncAt = Date()
        settingsStore.lastSyncNote = "门户录入 \(sessions.count) 节"
        await reminderScheduler.rebuild(sessions: scheduleStore.sessions, enabledTiers: settingsStore.enabledTiers)
        lastMessage = "已写入本机课表，并按已开启的提醒档位重建通知。"
        isPresentingLogin = false
    }

    func rebuildReminders() async {
        if !settingsStore.enabledTiers.isEmpty {
            let ok = await reminderScheduler.requestAuthorizationIfNeeded()
            if !ok {
                lastError = "通知权限未打开，提醒不会发出。请在系统设置中允许「课格」。"
            }
        }
        await reminderScheduler.rebuild(sessions: scheduleStore.sessions, enabledTiers: settingsStore.enabledTiers)
    }
}

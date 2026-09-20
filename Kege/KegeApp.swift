import SwiftUI
import Combine

@MainActor
final class AppDependencies: ObservableObject {
    let credentials: CredentialsStore
    let schedule: ScheduleStore
    let settings: SettingsStore
    let sync: SyncCoordinator

    init() {
        let credentials = CredentialsStore.shared
        credentials.ingestLocalSecretsFileIfPresent()
        let schedule = ScheduleStore()
        let settings = SettingsStore()
        self.credentials = credentials
        self.schedule = schedule
        self.settings = settings
        self.sync = SyncCoordinator(
            credentialsStore: credentials,
            scheduleStore: schedule,
            settingsStore: settings,
            reminderScheduler: .shared,
            loginSession: LoginWebViewSession()
        )
    }
}

@main
struct KegeApp: App {
    @StateObject private var deps = AppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(deps)
                .environmentObject(deps.schedule)
                .environmentObject(deps.settings)
                .environmentObject(deps.sync)
                .tint(KegeTheme.accent)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                deps.schedule.writeWidgetSnapshot()
                Task { await deps.sync.rebuildReminders() }
            }
        }
    }
}

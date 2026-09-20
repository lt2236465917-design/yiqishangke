import SwiftUI

struct RootView: View {
    @EnvironmentObject private var sync: SyncCoordinator
    @EnvironmentObject private var schedule: ScheduleStore

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "sun.max") }
            WeekView()
                .tabItem { Label("本周", systemImage: "square.grid.3x3") }
            ImportView()
                .tabItem { Label("导入", systemImage: "photo.on.rectangle") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .background(KegeTheme.paper)
        .sheet(isPresented: $sync.isPresentingLogin) {
            SchoolLoginView(
                session: sync.loginSession,
                onCancel: { sync.isPresentingLogin = false },
                onApply: { result, replace in
                    Task { await sync.applyParseResult(result, replace: replace) }
                }
            )
        }
        .alert("同步提示", isPresented: Binding(
            get: { sync.lastError != nil },
            set: { if !$0 { sync.lastError = nil } }
        )) {
            Button("好", role: .cancel) { sync.lastError = nil }
        } message: {
            Text(sync.lastError ?? "")
        }
    }
}

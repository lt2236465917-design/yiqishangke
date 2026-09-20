import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var sync: SyncCoordinator
    @EnvironmentObject private var schedule: ScheduleStore

    @State private var username = ""
    @State private var password = ""
    @State private var hasSavedCredentials = false
    @State private var aiKey = ""
    @State private var aiBase = AIVisionConfiguration.defaultBaseURL
    @State private var aiModel = AIVisionConfiguration.defaultModel
    @State private var aiPath = AIVisionConfiguration.defaultCompletionsPath
    @State private var hasAIKey = false
    @State private var banner: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reminderSection
                    credentialSection
                    syncSection
                    aiSection
                    aboutSection
                }
                .padding(20)
            }
            .background(KegeTheme.paper.ignoresSafeArea())
            .navigationTitle("设置")
            .onAppear(perform: load)
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("上课提醒")
                .font(KegeTheme.titleFont)
            Text("三档可独立开关，可同时开。课表变更后会重建通知。")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(ReminderTier.allCases) { tier in
                KegeCard {
                    Toggle(isOn: binding(for: tier)) {
                        HStack(spacing: 12) {
                            Image(systemName: tier.systemImage)
                                .font(.title2)
                                .foregroundStyle(KegeTheme.accent)
                                .frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tier.title)
                                    .font(.headline)
                                Text(tier.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(KegeTheme.accent)
                }
            }
        }
    }

    private var credentialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("学校账号")
                .font(KegeTheme.titleFont)
            Text("只写入本机钥匙串，不同步 iCloud，不会上传。密码不会出现在日志里。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            KegeCard {
                TextField("学号 / 用户名", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("密码", text: $password)
                HStack {
                    Button("保存到钥匙串") { saveCredentials() }
                        .buttonStyle(.borderedProminent)
                        .tint(KegeTheme.ink)
                    if hasSavedCredentials {
                        Button("删除", role: .destructive, action: deleteCredentials)
                    }
                }
                Text(hasSavedCredentials ? "钥匙串中已有账号 \(Redaction.username(username))" : "尚未保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("同步")
                .font(KegeTheme.titleFont)
            KegeCard {
                Text("首版只支持手动同步：打开学校登录页 → 自动填充 → 你点登录 → 进入课表后点右上角「录入课表」。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    sync.beginManualSync()
                } label: {
                    Label("立即同步课表", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(KegeTheme.accent)
                .padding(.top, 8)
                if !schedule.sessions.isEmpty {
                    Button("清空本机课表", role: .destructive) {
                        schedule.clear()
                        Task { await sync.rebuildReminders() }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("开发者识图（可选）")
                .font(KegeTheme.titleFont)
            Text("空表默认是 DeepSeek：`https://api.deepseek.com` + `deepseek-flash` + `/chat/completions`。Key、根路径、模型、补全路径都可改；下次请求只读钥匙串，厂商换模型不必重装。有 Key 走多模态 JSON；没 Key 才用本机 OCR。请求只发课表图片。不要把 Key 提交进 git。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            KegeCard {
                SecureField("API Key", text: $aiKey)
                    .textInputAutocapitalization(.never)
                TextField("接口根路径", text: $aiBase)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("模型名", text: $aiModel)
                    .textInputAutocapitalization(.never)
                TextField("补全路径（可选）", text: $aiPath)
                    .textInputAutocapitalization(.never)
                HStack {
                    Button("保存 Key") { saveAI() }
                    if hasAIKey {
                        Button("删除 Key", role: .destructive, action: deleteAI)
                    }
                }
                Text(hasAIKey ? "已保存开发者 Key（已隐藏）" : "未配置，截图导入将使用本机 Vision OCR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于课格")
                .font(KegeTheme.titleFont)
            Text("一起上课 · 中国艺术研究院课表本地查看。iOS 17+。不包含成绩、选课、校历门户其它功能，不上架。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if schedule.usingAppGroupFallback {
                Text("当前未读到 App Group 容器，小组件可能无法共享课表。请在 Xcode 为 App 与 Widget 勾选 group.cn.yiqishangke.Kege。")
                    .font(.footnote)
                    .foregroundStyle(KegeTheme.accent)
            }
            if let banner {
                Text(banner).font(.caption).foregroundStyle(KegeTheme.sage)
            }
        }
    }

    private func binding(for tier: ReminderTier) -> Binding<Bool> {
        Binding(
            get: { settings.isEnabled(tier) },
            set: { newValue in
                settings.set(tier, enabled: newValue)
                Task { await sync.rebuildReminders() }
            }
        )
    }

    private func load() {
        if let creds = try? CredentialsStore.shared.loadSchoolCredentials() {
            username = creds.username
            password = creds.password
            hasSavedCredentials = creds.isComplete
        }
        if let ai = try? CredentialsStore.shared.loadAIConfiguration() {
            aiKey = ai.apiKey
            aiBase = ai.resolvedBaseURL
            aiModel = ai.resolvedModel
            aiPath = ai.resolvedCompletionsPath
            hasAIKey = ai.isUsable
        }
    }

    private func saveCredentials() {
        do {
            try CredentialsStore.shared.saveSchoolCredentials(SchoolCredentials(username: username, password: password))
            hasSavedCredentials = true
            banner = "学校账号已写入钥匙串"
        } catch {
            banner = error.localizedDescription
        }
    }

    private func deleteCredentials() {
        do {
            try CredentialsStore.shared.deleteSchoolCredentials()
            username = ""
            password = ""
            hasSavedCredentials = false
            banner = "已从钥匙串删除学校账号"
        } catch {
            banner = error.localizedDescription
        }
    }

    private func saveAI() {
        do {
            try CredentialsStore.shared.saveAIConfiguration(
                AIVisionConfiguration(apiKey: aiKey, baseURL: aiBase, model: aiModel, completionsPath: aiPath)
            )
            hasAIKey = true
            banner = "识图 Key 已写入钥匙串"
        } catch {
            banner = error.localizedDescription
        }
    }

    private func deleteAI() {
        do {
            try CredentialsStore.shared.deleteAIConfiguration()
            aiKey = ""
            aiBase = AIVisionConfiguration.defaultBaseURL
            aiModel = AIVisionConfiguration.defaultModel
            aiPath = AIVisionConfiguration.defaultCompletionsPath
            hasAIKey = false
            banner = "已删除识图 Key"
        } catch {
            banner = error.localizedDescription
        }
    }
}

import SwiftUI
@preconcurrency import WebKit

struct SchoolLoginView: View {
    @ObservedObject var session: LoginWebViewSession
    @EnvironmentObject private var settings: SettingsStore
    var onCancel: () -> Void
    var onApply: (ParseResult, Bool) -> Void

    @State private var drafts: [EditableClassDraft] = []
    @State private var showingConfirm = false
    @State private var didWrite = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                instructionStrip
                ZStack {
                    WebViewContainer(webView: session.webView)
                    if let popup = session.popupWebView {
                        WebViewContainer(webView: popup)
                            .background(KegeTheme.paper)
                    }
                }
            }
            .background(KegeTheme.paper)
            .navigationTitle("学校登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onCancel)
                }
                if session.popupWebView != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("关闭新窗口") { session.dismissPopup() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("录入课表") {
                        Task { await session.userTappedParseCurrentPage() }
                    }
                    .disabled(isCapturing)
                }
            }
            .onChange(of: session.phase) { _, phase in
                if case .parsed(let result) = phase, !result.classes.isEmpty {
                    drafts = result.classes
                        .map(EditableClassDraft.init)
                        .sorted(by: EditableClassDraft.checklistOrder)
                    didWrite = false
                    showingConfirm = true
                }
            }
            .sheet(isPresented: $showingConfirm) {
                confirmationSheet
            }
        }
    }

    private var isCapturing: Bool {
        if case .parsing = session.phase { return true }
        return false
    }

    @ViewBuilder
    private var instructionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(bannerTitle)
                .font(.subheadline.weight(.semibold))
            Text(bannerDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = session.currentURL {
                Text(url.absoluteString)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            if session.isOnAppList {
                Button {
                    session.openGraduateManagement()
                } label: {
                    Text("进入研究生系统")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(KegeTheme.accent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor.opacity(0.12))
    }

    private var bannerTitle: String {
        if session.ssoBlocked {
            return "未能进入研究生系统"
        }
        if session.isOnAppList {
            return "应用列表：请点研究生综合管理"
        }
        if session.isOnWelcome {
            return "已登录，正在打开应用列表"
        }
        switch session.phase {
        case .idle:
            return "准备打开学校登录页"
        case .loading:
            return "正在加载"
        case .autoFilled:
            return "已填入登录名和密码（未填验证码，未点登录）"
        case .needsManualAuth:
            return "请手动完成验证"
        case .readyToParse:
            return "请进入课表后再录入"
        case .parsing:
            return "正在录入课表"
        case .parsed(let result):
            return result.classes.isEmpty ? "未识别到课程" : "识别到 \(result.classes.count) 节课"
        case .failed:
            return session.captureAttempt > 0 ? "录入课表失败" : "登录页受阻"
        }
    }

    private var bannerDetail: String {
        if session.ssoBlocked {
            return session.timetableHint.isEmpty ? LoginWebViewSession.tileClickFailedHint : session.timetableHint
        }
        if session.isOnAppList {
            return LoginWebViewSession.appListSSOHint
        }
        if session.isOnWelcome {
            return session.timetableHint.isEmpty ? LoginWebViewSession.openingAppListHint : session.timetableHint
        }
        switch session.phase {
        case .idle:
            return "凭证只在本机钥匙串，不会上传。"
        case .loading:
            return "目标 \(SchoolParser.loginURL.absoluteString)"
        case .autoFilled:
            return "请输入图形验证码，再亲自点蓝色「登录」。应用不会填写或绕过验证码。"
        case .needsManualAuth(let reason):
            return reason
        case .readyToParse:
            if !session.timetableHint.isEmpty {
                return session.timetableHint
            }
            if session.isOnGraduateFrameset {
                return "研究生系统是框架页。请点左侧「我的课表」后再点「录入课表」。"
            }
            return "进入课表页后再点「录入课表」。"
        case .parsing:
            let attempt = max(session.captureAttempt, 1)
            return "正在截取可见周课表并识别（第 \(attempt)/\(ScreenshotImporterError.maxAttempts) 次）。不会自动写入。"
        case .parsed(let result):
            return result.blocker ?? result.sourceDescription
        case .failed(let message):
            return message
        }
    }

    private var bannerColor: Color {
        if session.ssoBlocked { return .orange }
        if session.isOnAppList { return KegeTheme.accent }
        if session.isOnWelcome { return KegeTheme.sage }
        switch session.phase {
        case .failed:
            return KegeTheme.accent
        case .needsManualAuth:
            return .orange
        case .parsed(let r):
            return r.classes.isEmpty ? .orange : KegeTheme.sage
        case .autoFilled:
            return KegeTheme.sage
        default:
            return KegeTheme.ink.opacity(0.4)
        }
    }

    private var confirmationSheet: some View {
        NavigationStack {
            ScrollView {
                ScheduleImportChecklist(
                    engine: session.captureEngine.isEmpty ? "门户快照" : session.captureEngine,
                    drafts: drafts,
                    didWrite: didWrite,
                    replaceOnImport: $settings.replaceOnImport,
                    writeEnabled: !drafts.isEmpty && !didWrite,
                    onWrite: { applyCaptured() }
                )
                .padding(20)
            }
            .background(KegeTheme.paper.ignoresSafeArea())
            .navigationTitle("核对课表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showingConfirm = false }
                }
            }
        }
    }

    private func applyCaptured() {
        let result: ParseResult
        if case .parsed(let parsed) = session.phase, !parsed.classes.isEmpty {
            result = parsed
        } else {
            let sessions = drafts.compactMap { $0.asSession(source: .portal) }
            guard !sessions.isEmpty else { return }
            result = ParseResult(
                classes: sessions.map { session in
                    ParsedClassDraft(
                        title: session.title,
                        teacher: session.teacher,
                        location: session.location,
                        weekday: session.weekday,
                        startMinutes: session.startMinutes,
                        endMinutes: session.endMinutes,
                        weeks: session.weeks,
                        notes: session.notes
                    )
                },
                sourceDescription: "portal-snapshot-confirmed",
                blocker: nil,
                rawExcerpt: nil
            )
        }
        didWrite = true
        onApply(result, settings.replaceOnImport)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

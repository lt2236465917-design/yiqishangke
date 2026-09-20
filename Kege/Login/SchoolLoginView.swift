import SwiftUI
@preconcurrency import WebKit

struct SchoolLoginView: View {
    /// Shown in the login banner so a stale App install is obvious.
    static let loginSheetStamp = "PENDING"

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
                singleInstructionBanner
                webArea
            }
            .background(KegeTheme.paper)
            .navigationTitle("学校登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCancel) {
                        Text(verbatim: "关闭")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if session.popupWebView != nil {
                            Button {
                                session.dismissPopup()
                            } label: {
                                Text(verbatim: "关闭新窗口")
                            }
                        }
                        Button {
                            Task { await session.userTappedParseCurrentPage() }
                        } label: {
                            Text(verbatim: "录入课表")
                        }
                        .disabled(isCapturing)
                    }
                }
            }
            .onChange(of: session.phase) { _, phase in
                if case .parsed(let result) = phase, !result.classes.isEmpty {
                    drafts = result.classes
                        .map(EditableClassDraft.init)
                        .sorted(by: EditableClassDraft.checklistOrder)
                    didWrite = false
                    showingConfirm = true
                } else {
                    showingConfirm = false
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

    /// Full-bleed WebView. No bottom inset, no button overlay, no stacked chrome.
    private var webArea: some View {
        ZStack {
            WebViewContainer(webView: session.webView)
            if let popup = session.popupWebView {
                WebViewContainer(webView: popup)
                    .background(KegeTheme.paper)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One strip above the WebView. User opens 研究生综合管理 from the portal tile.
    private var singleInstructionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: bannerLine)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: "build \(Self.loginSheetStamp)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor.opacity(0.12))
    }

    private var bannerLine: String {
        if session.ssoBlocked {
            let hint = session.timetableHint.isEmpty
                ? LoginWebViewSession.tileClickFailedHint
                : session.timetableHint
            return hint
        }
        if session.isOnAppList {
            return LoginWebViewSession.appListSSOHint
        }
        if session.isOnWelcome {
            return session.timetableHint.isEmpty
                ? LoginWebViewSession.openingAppListHint
                : session.timetableHint
        }
        switch session.phase {
        case .idle:
            return "凭证只在本机钥匙串，不会上传。"
        case .loading:
            return "正在打开学校登录页。"
        case .autoFilled:
            return "已填登录名和密码。请手输验证码，再亲自点蓝色「登录」。"
        case .needsManualAuth(let reason):
            return reason
        case .readyToParse:
            if !session.timetableHint.isEmpty {
                return session.timetableHint
            }
            if session.isOnGraduateFrameset {
                return "请点左侧「我的课表」，再点右上角「录入课表」。"
            }
            return "进入课表页后，点右上角「录入课表」。"
        case .parsing:
            return session.timetableHint.isEmpty
                ? "正在从网页表格提取课表。不会自动写入。"
                : session.timetableHint
        case .parsed(let result):
            if result.classes.isEmpty {
                return result.blocker ?? "未识别到课程。可换页后再点右上角「录入课表」。"
            }
            return "识别到 \(result.classes.count) 节课。请核对后再写入。"
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
                    engine: session.captureEngine.isEmpty ? "HTML 周课表" : session.captureEngine,
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingConfirm = false
                    } label: {
                        Text(verbatim: "关闭")
                    }
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

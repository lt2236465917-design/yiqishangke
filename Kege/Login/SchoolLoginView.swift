import SwiftUI
import WebKit

struct SchoolLoginView: View {
    @ObservedObject var session: LoginWebViewSession
    var onCancel: () -> Void
    var onApply: (ParseResult) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBanner
                if session.isOnAppList {
                    appListOffer
                }
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
                    Button("解析本页") {
                        Task { await session.userTappedParseCurrentPage() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bannerColor.opacity(0.12))
    }

    private var bannerTitle: String {
        if session.isOnAppList { return "应用列表：请点研究生综合管理" }
        switch session.phase {
        case .idle: "准备打开学校登录页"
        case .loading: "正在加载"
        case .autoFilled: "已填入登录名和密码（未填验证码，未点登录）"
        case .needsManualAuth: "请手动完成验证"
        case .readyToParse: "请进入课表后再解析"
        case .parsing: "正在解析本页"
        case .parsed(let result): result.classes.isEmpty ? "未解析到课程" : "解析到 \(result.classes.count) 门课"
        case .failed: "登录页受阻"
        }
    }

    private var bannerDetail: String {
        if session.isOnAppList {
            return "请点应用列表里的研究生综合管理；直达裸开会丢登录态"
        }
        switch session.phase {
        case .idle:
            "凭证只在本机钥匙串，不会上传。"
        case .loading:
            "目标 \(SchoolParser.loginURL.absoluteString)"
        case .autoFilled:
            "请输入图形验证码，再亲自点蓝色「登录」。应用不会填写或绕过验证码。"
        case .needsManualAuth(let reason):
            reason
        case .readyToParse:
            if !session.timetableHint.isEmpty {
                session.timetableHint
            } else if session.isOnGraduateFrameset {
                "研究生系统是框架页。请点左侧「我的课表」后再点「解析本页」。"
            } else {
                "进入课表页后再点「解析本页」。"
            }
        case .parsing:
            "使用 zgysyjy 解析脚本，不是 AI 点选。"
        case .parsed(let result):
            result.blocker ?? result.sourceDescription
        case .failed(let message):
            message
        }
    }

    private var bannerColor: Color {
        if session.isOnAppList { return KegeTheme.accent }
        switch session.phase {
        case .failed: return KegeTheme.accent
        case .needsManualAuth: return .orange
        case .parsed(let r): return r.classes.isEmpty ? .orange : KegeTheme.sage
        case .autoFilled: return KegeTheme.sage
        default: return KegeTheme.ink.opacity(0.4)
        }
    }

    private var appListOffer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("请点应用列表里的研究生综合管理；直达裸开会丢登录态")
                .font(.subheadline.weight(.semibold))
            Text("下面按钮会在本页点那个磁贴，走门户单点登录。不要自己打开 frameset.jsp。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KegeTheme.accent.opacity(0.12))
    }

    @ViewBuilder
    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                session.openGraduateManagement()
            } label: {
                Text("进入研究生系统")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(KegeTheme.accent)

            Button {
                Task { await session.userTappedParseCurrentPage() }
            } label: {
                Text("解析本页")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if case .parsed(let result) = session.phase {
                if result.classes.isEmpty {
                    Text("主路径解析未拿到课表。可继续换页再解析，或关闭后改用截图导入。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        onApply(result)
                    } label: {
                        Text("写入本机课表（\(result.classes.count)）")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(KegeTheme.sage)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

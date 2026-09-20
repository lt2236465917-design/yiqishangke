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
                WebViewContainer(webView: session.webView)
            }
            .background(KegeTheme.paper)
            .navigationTitle("学校登录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("解析本页") {
                        Task { await session.userTappedParseCurrentPage() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                resultBar
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
        switch session.phase {
        case .idle: "准备打开学校登录页"
        case .loading: "正在加载"
        case .autoFilled: "已填入学号和密码（未代点登录）"
        case .needsManualAuth: "请手动完成验证"
        case .readyToParse: "请登录后进入课表页"
        case .parsing: "正在解析本页"
        case .parsed(let result): result.classes.isEmpty ? "未解析到课程" : "解析到 \(result.classes.count) 门课"
        case .failed: "登录页受阻"
        }
    }

    private var bannerDetail: String {
        switch session.phase {
        case .idle:
            "凭证只在本机钥匙串，不会上传。"
        case .loading:
            "目标 \(SchoolParser.loginURL.absoluteString)"
        case .autoFilled:
            "请你亲自点「登录」。遇到验证码或二次验证时，应用不会自动点击。"
        case .needsManualAuth(let reason):
            reason
        case .readyToParse:
            "课后课表地址尚未核实。登录后请进入课表，再点右上角「解析本页」。"
        case .parsing:
            "使用 zgysyjy 解析脚本，不是 AI 点选。"
        case .parsed(let result):
            result.blocker ?? result.sourceDescription
        case .failed(let message):
            message
        }
    }

    private var bannerColor: Color {
        switch session.phase {
        case .failed: KegeTheme.accent
        case .needsManualAuth: .orange
        case .parsed(let r): r.classes.isEmpty ? .orange : KegeTheme.sage
        case .autoFilled: KegeTheme.sage
        default: KegeTheme.ink.opacity(0.4)
        }
    }

    @ViewBuilder
    private var resultBar: some View {
        if case .parsed(let result) = session.phase {
            VStack(spacing: 10) {
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
                    .tint(KegeTheme.accent)
                }
            }
            .padding()
            .background(.ultraThinMaterial)
        }
    }
}

private struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

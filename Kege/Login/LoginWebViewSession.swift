import Foundation
import WebKit
import Combine

enum LoginSessionPhase: Equatable {
    case idle
    case loading(URL)
    case autoFilled
    case needsManualAuth(String)
    case readyToParse
    case parsing
    case parsed(ParseResult)
    case failed(String)
}

@MainActor
final class LoginWebViewSession: NSObject, ObservableObject {
    @Published var phase: LoginSessionPhase = .idle
    @Published var currentURL: URL?
    @Published var didAttemptAutoFill = false

    let webView: WKWebView
    private let parser: SchoolParsing
    private var credentials: SchoolCredentials?

    init(parser: SchoolParsing = ZgysyjyParser()) {
        self.parser = parser
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func start(credentials: SchoolCredentials) {
        self.credentials = credentials
        didAttemptAutoFill = false
        phase = .loading(SchoolParser.loginURL)
        SafeLog.info("Starting school login WebView (ephemeral). Username \(Redaction.username(credentials.username))")
        webView.load(URLRequest(url: SchoolParser.loginURL))
    }

    func userTappedParseCurrentPage() async {
        await parseCurrentPage()
    }

    func parseCurrentPage() async {
        phase = .parsing
        do {
            let result = try await webView.evaluateJavaScript(EmbeddedScripts.extractPage)
            let payload = Self.decodeExtract(result)
            let parsed = parser.parse(html: payload.html, pageURL: payload.url, innerText: payload.innerText)
            phase = .parsed(parsed)
            SafeLog.info("Parsed current page classes=\(parsed.classes.count) url=\(payload.url?.absoluteString ?? "unknown")")
        } catch {
            phase = .failed("解析脚本执行失败：\(error.localizedDescription)")
        }
    }

    private func attemptAutoFillIfNeeded() async {
        guard let credentials, credentials.isComplete else { return }
        if case .needsManualAuth = phase { return }
        if case .parsed = phase { return }
        if case .parsing = phase { return }

        do {
            let raw = try await webView.callAsyncJavaScript(
                EmbeddedScripts.autoFill,
                arguments: [
                    "username": credentials.username,
                    "password": credentials.password
                ],
                in: nil,
                in: .page
            )
            // Password is passed only as a JS argument — never interpolated into logs.
            let filled = (raw as? [String: Any])?["filled"] as? Bool ?? false
            let halted = (raw as? [String: Any])?["halted"] as? Bool ?? false
            let reason = (raw as? [String: Any])?["reason"] as? String ?? ""
            if halted {
                phase = .needsManualAuth("检测到验证码或二次验证，已停止自动填充。请你手动完成登录。")
                SafeLog.info("Auto-fill halted: \(reason)")
                return
            }
            if filled {
                didAttemptAutoFill = true
                phase = .autoFilled
                SafeLog.info("Auto-fill completed (no submit)")
            } else {
                phase = .readyToParse
                SafeLog.info("Auto-fill skipped: \(reason)")
            }
        } catch {
            phase = .readyToParse
            SafeLog.error("Auto-fill script error: \(error.localizedDescription)")
        }
    }

    private struct ExtractedPage {
        var url: URL?
        var html: String
        var innerText: String?
    }

    private static func decodeExtract(_ raw: Any) -> ExtractedPage {
        let dict: [String: Any]
        if let mapped = raw as? [String: Any] {
            dict = mapped
        } else if let ns = raw as? NSDictionary {
            var mapped: [String: Any] = [:]
            for (key, value) in ns {
                if let key = key as? String {
                    mapped[key] = value
                }
            }
            dict = mapped
        } else {
            dict = [:]
        }
        let url = (dict["url"] as? String).flatMap(URL.init(string:))
        let html = dict["html"] as? String ?? ""
        let text = dict["innerText"] as? String
        return ExtractedPage(url: url, html: html, innerText: text)
    }
}

extension LoginWebViewSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        currentURL = webView.url
        if case .needsManualAuth = phase { return }
        if case .parsed = phase { return }
        if let url = webView.url {
            phase = .loading(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        currentURL = webView.url
        Task { await attemptAutoFillIfNeeded() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        phase = .failed("页面加载失败：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        phase = .failed("无法打开学校登录页：\(error.localizedDescription)。若在校外，可能需要校园网或 VPN。")
    }
}

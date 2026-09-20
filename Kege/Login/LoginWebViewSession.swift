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
    @Published private(set) var isOnAppList = false

    let webView: WKWebView
    /// Popup created by `window.open` / `target=_blank` when the request has no concrete URL yet.
    @Published var popupWebView: WKWebView?
    private let parser: SchoolParsing
    private var credentials: SchoolCredentials?
    private var didOpenGraduate = false

    static let desktopSafariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    init(parser: SchoolParsing = ZgysyjyParser()) {
        self.parser = parser
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.desktopSafariUA
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    func dismissPopup() {
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupWebView?.stopLoading()
        popupWebView = nil
    }

    private var activeWebView: WKWebView {
        popupWebView ?? webView
    }

    func start(credentials: SchoolCredentials) {
        self.credentials = credentials
        didAttemptAutoFill = false
        didOpenGraduate = false
        isOnAppList = false
        phase = .loading(SchoolParser.loginURL)
        SafeLog.info("Starting school login WebView (ephemeral). Username \(Redaction.username(credentials.username))")
        dismissPopup()
        webView.load(URLRequest(url: SchoolParser.loginURL))
    }

    func openGraduateManagement() {
        didOpenGraduate = true
        isOnAppList = false
        dismissPopup()
        phase = .readyToParse
        SafeLog.info("Opening graduate frameset")
        webView.load(URLRequest(url: SchoolParser.graduateFramesetURL))
    }

    private func remember(url: URL?) {
        currentURL = url
        isOnAppList = PortalNavigation.isAppList(url)
    }

    private func syncURLFromPage(_ webView: WKWebView) async {
        if let href = try? await webView.evaluateJavaScript("String(location.href)") as? String,
           let url = URL(string: href) {
            remember(url: url)
            return
        }
        remember(url: webView.url)
    }

    private func openGraduateIfReady(from webView: WKWebView) async {
        await syncURLFromPage(webView)
        guard !didOpenGraduate else { return }
        guard PortalNavigation.shouldOpenGraduate(from: currentURL ?? webView.url) else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        await syncURLFromPage(webView)
        guard !didOpenGraduate, PortalNavigation.shouldOpenGraduate(from: currentURL ?? webView.url) else { return }
        openGraduateManagement()
    }

    func userTappedParseCurrentPage() async {
        await parseCurrentPage()
    }

    func parseCurrentPage() async {
        phase = .parsing
        do {
            let result = try await activeWebView.evaluateJavaScript(EmbeddedScripts.extractPage)
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
        if didAttemptAutoFill { return }
        if case .needsManualAuth = phase { return }
        if case .parsed = phase { return }
        if case .parsing = phase { return }

        do {
            let raw = try await activeWebView.callAsyncJavaScript(
                EmbeddedScripts.autoFill,
                arguments: [
                    "username": credentials.username,
                    "password": credentials.password
                ],
                in: nil,
                in: .page
            )
            // Password is passed only as a JS argument — never interpolated into logs.
            let dict = Self.dictionary(from: raw)
            let filled = dict["filled"] as? Bool ?? false
            let halted = dict["halted"] as? Bool ?? false
            let captchaPresent = dict["captchaPresent"] as? Bool ?? false
            let reason = dict["reason"] as? String ?? ""
            if halted {
                phase = .needsManualAuth("检测到短信或二次验证，已停止自动填充。请你手动完成。")
                SafeLog.info("Auto-fill halted: \(reason)")
                return
            }
            if filled {
                didAttemptAutoFill = true
                phase = .autoFilled
                SafeLog.info("Auto-fill completed (no submit, captchaPresent=\(captchaPresent), reason=\(reason))")
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

    private static func dictionary(from raw: Any?) -> [String: Any] {
        if let mapped = raw as? [String: Any] {
            return mapped
        }
        if let ns = raw as? NSDictionary {
            var mapped: [String: Any] = [:]
            for (key, value) in ns {
                if let key = key as? String {
                    mapped[key] = value
                }
            }
            return mapped
        }
        return [:]
    }

    private static func decodeExtract(_ raw: Any) -> ExtractedPage {
        let dict = dictionary(from: raw)
        let url = (dict["url"] as? String).flatMap(URL.init(string:))
        let html = dict["html"] as? String ?? ""
        let text = dict["innerText"] as? String
        return ExtractedPage(url: url, html: html, innerText: text)
    }
}

extension LoginWebViewSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        preferences.allowsContentJavaScript = true
        let url = navigationAction.request.url
        if let url, !PortalNavigation.allows(url, from: webView.url ?? currentURL) {
            SafeLog.info("Blocked navigation host: \(url.host ?? url.absoluteString)")
            decisionHandler(.cancel, preferences)
            return
        }
        if navigationAction.targetFrame == nil, let url, PortalNavigation.hasConcreteHTTPURL(url) {
            webView.load(navigationAction.request)
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        remember(url: webView.url)
        if case .needsManualAuth = phase { return }
        if case .parsed = phase { return }
        if PortalNavigation.isGraduateFrameset(webView.url) {
            phase = .readyToParse
            return
        }
        if PortalNavigation.isSchoolPortal(webView.url) {
            phase = .readyToParse
            return
        }
        if let url = webView.url {
            phase = .loading(url)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        remember(url: webView.url)
        if PortalNavigation.isGraduateFrameset(webView.url) || PortalNavigation.isSchoolPortal(webView.url) {
            if case .parsed = phase { } else {
                phase = .readyToParse
            }
        }
        Task {
            await attemptAutoFillIfNeeded()
            if !didAttemptAutoFill {
                try? await Task.sleep(nanoseconds: 450_000_000)
                await attemptAutoFillIfNeeded()
            }
            await openGraduateIfReady(from: webView)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        phase = .failed("页面加载失败：\(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        phase = .failed("无法打开学校页面：\(error.localizedDescription)。若在校外，可能需要校园网或 VPN。")
    }
}

extension LoginWebViewSession: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, PortalNavigation.hasConcreteHTTPURL(url) {
            if PortalNavigation.allows(url, from: webView.url ?? currentURL) {
                SafeLog.info("Opening portal window in same WebView: \(url.host ?? "")")
                webView.load(navigationAction.request)
            } else {
                SafeLog.info("Blocked popup host: \(url.host ?? url.absoluteString)")
            }
            return nil
        }

        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let child = WKWebView(frame: webView.bounds, configuration: configuration)
        child.customUserAgent = Self.desktopSafariUA
        child.allowsBackForwardNavigationGestures = true
        child.navigationDelegate = self
        child.uiDelegate = self
        popupWebView = child
        SafeLog.info("Created in-sheet child WebView for window.open")
        return child
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popupWebView {
            dismissPopup()
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        SafeLog.info("Portal JS alert (not logged as credentials)")
        completionHandler()
    }
}

enum PortalNavigation {
    static let allowedSuffixes = [
        "zgysyjy.org.cn",
        "wxt.zgysyjy.org.cn",
        "gscaa.cn"
    ]

    static func hasConcreteHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        guard scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }

    static func isLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path.contains("/am/mlogin") || path.contains("login.html")
    }

    static func isGraduateFrameset(_ url: URL?) -> Bool {
        ZgysyjyParser.isGraduateFrameset(url)
    }

    static func isAppList(_ url: URL?) -> Bool {
        guard let url else { return false }
        if isLoginPage(url) || isGraduateFrameset(url) { return false }
        let blob = (url.absoluteString + " " + url.path + " " + (url.fragment ?? "")).lowercased()
        return blob.contains("applist") || blob.contains("app-list") || blob.contains("/portal")
    }

    static func isSchoolPortal(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return false }
        guard isAllowedHost(host) else { return false }
        if isLoginPage(url) || isGraduateFrameset(url) { return false }
        return isAppList(url)
    }

    static func shouldOpenGraduate(from url: URL?) -> Bool {
        isAppList(url) || isSchoolPortal(url)
    }

    static func allows(_ url: URL, from current: URL?) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme.isEmpty || ["about", "blob", "data", "javascript"].contains(scheme) {
            return true
        }
        guard scheme == "http" || scheme == "https" else { return false }
        if isAllowedHost(url.host) { return true }
        if let current, isAllowedHost(current.host) {
            SafeLog.info("Allowing hop from school portal to \(url.host ?? "unknown")")
            return true
        }
        return false
    }

    static func isAllowedHost(_ host: String?) -> Bool {
        guard let host else { return false }
        let lowered = host.lowercased()
        return allowedSuffixes.contains { lowered == $0 || lowered.hasSuffix(".\($0)") }
    }
}

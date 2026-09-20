import Foundation
@preconcurrency import WebKit
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
    @Published private(set) var isOnWelcome = false
    @Published private(set) var isOnGraduateFrameset = false
    @Published private(set) var timetableHint = ""
    /// Tile click failed or graduate page is a login wall. Never auto-jump to naked frameset.
    @Published private(set) var ssoBlocked = false

    let webView: WKWebView
    /// Popup created by `window.open` / `target=_blank` when the request has no concrete URL yet.
    @Published var popupWebView: WKWebView?
    private let parser: SchoolParsing
    private var credentials: SchoolCredentials?
    private var didClickMyTimetable = false
    /// Set only when the user taps 「进入研究生系统」 while not yet on appList.
    private var pendingGraduateTileClick = false
    /// IAM welcome/user-center → appList, at most once per session.
    private var didRedirectToAppList = false
    private var appListRedirectInFlight = false
    private var urlObservations: [NSKeyValueObservation] = []

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
        observeURL(of: webView)
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
        didClickMyTimetable = false
        pendingGraduateTileClick = false
        didRedirectToAppList = false
        appListRedirectInFlight = false
        isOnAppList = false
        isOnWelcome = false
        isOnGraduateFrameset = false
        timetableHint = ""
        ssoBlocked = false
        phase = .loading(SchoolParser.loginURL)
        SafeLog.info("Starting school login WebView (ephemeral). Username \(Redaction.username(credentials.username))")
        dismissPopup()
        loadSchoolPage(SchoolParser.loginURL, in: webView)
    }

    func openGraduateManagement() {
        Task { await openGraduateViaPortalSSO() }
    }

    /// User retry from welcome/user-center. Does not click the graduate tile.
    func openApplicationList() {
        Task {
            didRedirectToAppList = true
            await navigateToAppList(in: activeWebView)
        }
    }

    /// Never loads naked frameset. Stays on / returns to appList, then clicks the portal tile for SSO.
    private func openGraduateViaPortalSSO() async {
        didClickMyTimetable = false
        ssoBlocked = false
        await syncURLFromPage(activeWebView)
        if PortalNavigation.isAppList(currentURL ?? activeWebView.url) {
            await clickGraduateTile(from: activeWebView)
            return
        }
        pendingGraduateTileClick = true
        timetableHint = Self.openingAppListHint
        phase = .readyToParse
        SafeLog.info("Not on appList; opening portal appList for SSO tile click (not frameset)")
        await navigateToAppList(in: webView)
        await syncURLFromPage(webView)
        if PortalNavigation.isAppList(currentURL ?? webView.url) {
            await clickGraduateTile(from: webView)
        }
    }

    /// Programmatic loads never touch naked `frameset.jsp`. Hash-router landings still update the banner.
    private func loadSchoolPage(_ url: URL, in webView: WKWebView) {
        if PortalNavigation.isBareGraduateFrameset(url) {
            SafeLog.info("Refusing naked graduate frameset load")
            markSSOBlocked(Self.loginWallHint)
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func observeURL(of webView: WKWebView) {
        let observation = webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            Task { @MainActor in
                self?.handleObservedURL(view.url)
            }
        }
        urlObservations.append(observation)
    }

    private func handleObservedURL(_ url: URL?) {
        remember(url: url)
        if PortalNavigation.isAppList(url) {
            switch phase {
            case .parsed, .parsing, .failed, .needsManualAuth:
                break
            default:
                phase = .readyToParse
            }
            return
        }
        if PortalNavigation.isIAMPostLogin(url) {
            Task { await maybeOpenAppListAfterLogin(from: webView) }
        }
    }

    static let appListSSOHint = "请点应用列表里的研究生综合管理；直达裸开会丢登录态"
    static let openingAppListHint = "已登录。正在打开应用列表（个人中心没有研究生磁贴）。"
    static let tileClickFailedHint = "未能点开「研究生综合管理」。请亲手点应用列表里的磁贴。点不开或出现「请登录」时，请关闭本页，改用「导入」里的截图。"
    static let loginWallHint = "研究生系统在要登录，说明没带上门户会话。不要直达裸 frameset。请关闭本页，改用「导入」里的截图。"

    private func markSSOBlocked(_ message: String) {
        ssoBlocked = true
        timetableHint = message
        phase = .readyToParse
    }

    private func remember(url: URL?) {
        currentURL = url
        isOnAppList = PortalNavigation.isAppList(url)
        isOnWelcome = PortalNavigation.isIAMPostLogin(url)
        isOnGraduateFrameset = PortalNavigation.isGraduateFrameset(url)
        if isOnAppList, !ssoBlocked {
            timetableHint = Self.appListSSOHint
        } else if isOnWelcome, !ssoBlocked, !didRedirectToAppList {
            timetableHint = Self.openingAppListHint
        }
    }

    private func syncURLFromPage(_ webView: WKWebView) async {
        if let href = try? await webView.evaluateJavaScript("String(location.href)") as? String,
           let url = URL(string: href) {
            remember(url: url)
            return
        }
        remember(url: webView.url)
    }

    /// After IAM login, welcome/user-center has no graduate tile. Open appList once. Never frameset.
    private func maybeOpenAppListAfterLogin(from webView: WKWebView) async {
        if didRedirectToAppList || appListRedirectInFlight { return }
        if PortalNavigation.isAppList(webView.url) || PortalNavigation.isAppList(currentURL) { return }
        if PortalNavigation.isLoginPage(webView.url) || PortalNavigation.isLoginPage(currentURL) { return }
        if PortalNavigation.isGraduateHost(webView.url) || PortalNavigation.isGraduateFrameset(webView.url) { return }
        guard PortalNavigation.isIAMHost(webView.url) || PortalNavigation.isIAMHost(currentURL) else { return }

        appListRedirectInFlight = true
        defer { appListRedirectInFlight = false }

        await syncURLFromPage(webView)
        let url = currentURL ?? webView.url
        if PortalNavigation.isAppList(url) { return }
        if PortalNavigation.isLoginPage(url) { return }
        if PortalNavigation.isGraduateHost(url) || PortalNavigation.isGraduateFrameset(url) { return }
        if let url, PortalNavigation.looksLikeSSOEntry(url) { return }
        guard PortalNavigation.isIAMHost(url) else { return }

        let loggedIn = await detectLoggedInIAM(from: webView)
        let welcomeURL = PortalNavigation.isIAMPostLogin(url)
        guard loggedIn || welcomeURL else { return }

        didRedirectToAppList = true
        timetableHint = Self.openingAppListHint
        phase = .readyToParse
        SafeLog.info("IAM login landed off appList; opening portal hash appList once")
        await navigateToAppList(in: webView)
    }

    private func detectLoggedInIAM(from webView: WKWebView) async -> Bool {
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.detectIAMSession)
            let dict = Self.dictionary(from: raw)
            if dict["loginForm"] as? Bool == true { return false }
            if dict["hasAppListHash"] as? Bool == true { return false }
            if dict["welcome"] as? Bool == true { return true }
            if dict["logout"] as? Bool == true { return true }
        } catch {
            SafeLog.error("IAM session script: \(error.localizedDescription)")
        }
        return await hasIAMCookies(from: webView) && PortalNavigation.isIAMPostLogin(currentURL ?? webView.url)
    }

    private func hasIAMCookies(from webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let hit = cookies.contains { cookie in
                    let domain = cookie.domain.lowercased()
                    return domain.contains("iam.zgysyjy.org.cn") || domain.hasSuffix("zgysyjy.org.cn")
                }
                continuation.resume(returning: hit)
            }
        }
    }

    private func navigateToAppList(in webView: WKWebView) async {
        if PortalNavigation.isBareGraduateFrameset(webView.url) { return }
        timetableHint = Self.openingAppListHint
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.goToAppList)
            let dict = Self.dictionary(from: raw)
            SafeLog.info("appList hash method=\(dict["method"] as? String ?? "")")
        } catch {
            SafeLog.error("appList hash script: \(error.localizedDescription)")
        }
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 280_000_000)
            await syncURLFromPage(webView)
            if PortalNavigation.isAppList(currentURL ?? webView.url) {
                timetableHint = Self.appListSSOHint
                phase = .readyToParse
                SafeLog.info("Landed on portal appList")
                return
            }
        }
        SafeLog.info("Hash did not stick; loading portal appList URL (not frameset)")
        loadSchoolPage(SchoolParser.portalAppListURL, in: webView)
    }

    private func clickGraduateTile(from webView: WKWebView) async {
        pendingGraduateTileClick = false
        timetableHint = "正在点应用列表里的「研究生综合管理」，以保留门户登录态…"
        for attempt in 0..<3 {
            do {
                let raw = try await webView.evaluateJavaScript(EmbeddedScripts.openGraduateTile)
                let dict = Self.dictionary(from: raw)
                let clicked = dict["clicked"] as? Bool ?? false
                let href = dict["href"] as? String ?? ""
                if let url = PortalNavigation.resolvedSSOURL(href, relativeTo: currentURL ?? webView.url) {
                    SafeLog.info("Loading discovered SSO host=\(url.host ?? "")")
                    loadSchoolPage(url, in: webView)
                    timetableHint = "已通过门户单点登录跳转。进入课表后点「解析本页」。"
                    return
                }
                if clicked {
                    timetableHint = "已尝试点开「研究生综合管理」。等跳转完成后打开「我的课表」，再点「解析本页」。"
                    SafeLog.info("Clicked graduate tile method=\(dict["method"] as? String ?? "")")
                    return
                }
            } catch {
                SafeLog.error("Graduate tile script: \(error.localizedDescription)")
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        markSSOBlocked(Self.tileClickFailedHint)
        SafeLog.info("Graduate tile click not found")
    }

    private func finishPendingTileClickIfNeeded(from webView: WKWebView) async {
        guard pendingGraduateTileClick else { return }
        await syncURLFromPage(webView)
        guard PortalNavigation.isAppList(currentURL ?? webView.url) else { return }
        await clickGraduateTile(from: webView)
    }

    @discardableResult
    private func detectGraduateLoginWall(from webView: WKWebView) async -> Bool {
        guard PortalNavigation.isGraduateHost(currentURL ?? webView.url) else { return false }
        defer { logCookieDomains(from: webView) }
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.detectGraduateLoginWall)
            let dict = Self.dictionary(from: raw)
            if dict["loginWall"] as? Bool == true {
                markSSOBlocked(Self.loginWallHint)
                SafeLog.info("Graduate page login wall")
                return true
            }
        } catch {
            SafeLog.error("Login-wall script: \(error.localizedDescription)")
        }
        return false
    }

    private func logCookieDomains(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let domains = Array(Set(cookies.map(\.domain))).sorted()
            SafeLog.info("Cookie domains: \(domains.joined(separator: ", ")) count=\(cookies.count)")
        }
    }

    private func openMyTimetableIfPossible(from webView: WKWebView) async {
        await syncURLFromPage(webView)
        guard PortalNavigation.isGraduateFrameset(currentURL ?? webView.url) else { return }
        guard !didClickMyTimetable else { return }
        didClickMyTimetable = true
        for attempt in 0..<2 {
            do {
                let raw = try await webView.evaluateJavaScript(EmbeddedScripts.openMyTimetable)
                let dict = Self.dictionary(from: raw)
                if dict["clicked"] as? Bool == true {
                    timetableHint = "已尝试打开「我的课表」。确认左侧高亮且出现课表后再点「解析本页」。"
                    SafeLog.info("Clicked 我的课表 in graduate frameset")
                    return
                }
            } catch {
                timetableHint = "请点左侧「我的课表」，再点「解析本页」。"
                SafeLog.error("我的课表 script error: \(error.localizedDescription)")
            }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        timetableHint = "未能自动点开「我的课表」。请在左侧菜单亲手点一下，再点「解析本页」。"
        SafeLog.info("我的课表 click not found")
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
        if PortalNavigation.isGraduateFrameset(webView.url) || PortalNavigation.isGraduateHost(webView.url) {
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
        if PortalNavigation.isGraduateFrameset(webView.url)
            || PortalNavigation.isGraduateHost(webView.url)
            || PortalNavigation.isSchoolPortal(webView.url) {
            if case .parsed = phase { } else {
                phase = .readyToParse
            }
        }
        Task {
            await syncURLFromPage(webView)
            await attemptAutoFillIfNeeded()
            if !didAttemptAutoFill {
                try? await Task.sleep(nanoseconds: 450_000_000)
                await attemptAutoFillIfNeeded()
            }
            await finishPendingTileClickIfNeeded(from: webView)
            await maybeOpenAppListAfterLogin(from: webView)
            let loginWall = await detectGraduateLoginWall(from: webView)
            if !loginWall, !ssoBlocked {
                await openMyTimetableIfPossible(from: webView)
            }
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

        configuration.websiteDataStore = webView.configuration.websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let child = WKWebView(frame: webView.bounds, configuration: configuration)
        child.customUserAgent = Self.desktopSafariUA
        child.allowsBackForwardNavigationGestures = true
        child.navigationDelegate = self
        child.uiDelegate = self
        popupWebView = child
        observeURL(of: child)
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

    static func isIAMHost(_ url: URL?) -> Bool {
        (url?.host?.lowercased() ?? "").contains("iam.zgysyjy.org.cn")
    }

    static func isLoginPage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path.contains("/am/mlogin") || path.contains("login.html")
    }

    static func isGraduateFrameset(_ url: URL?) -> Bool {
        ZgysyjyParser.isGraduateFrameset(url)
    }

    static func isGraduateHost(_ url: URL?) -> Bool {
        ZgysyjyParser.isGraduateHost(url)
    }

    /// Real application list only. `/portal` welcome/user-center is not appList.
    static func isAppList(_ url: URL?) -> Bool {
        guard let url else { return false }
        if isLoginPage(url) || isGraduateFrameset(url) || isGraduateHost(url) { return false }
        let fragment = (url.fragment ?? "").lowercased()
        let path = url.path.lowercased()
        let abs = url.absoluteString.lowercased()
        return fragment.contains("applist")
            || fragment.contains("app-list")
            || path.contains("applist")
            || path.contains("app-list")
            || abs.contains("#/applist")
            || abs.contains("#/app-list")
    }

    /// Logged-in IAM page that is not the application list (welcome / user-center / portal shell).
    static func isIAMPostLogin(_ url: URL?) -> Bool {
        guard isIAMHost(url), !isLoginPage(url), !isAppList(url) else { return false }
        if isGraduateHost(url) || isGraduateFrameset(url) { return false }
        if let url, looksLikeSSOEntry(url) { return false }
        return true
    }

    static func isSchoolPortal(_ url: URL?) -> Bool {
        isAppList(url) || isIAMPostLogin(url)
    }

    /// Ticketed / oauth hops are OK. Bare frameset.jsp without query is not an SSO entry.
    static func looksLikeSSOEntry(_ url: URL) -> Bool {
        if isBareGraduateFrameset(url) { return false }
        let blob = url.absoluteString.lowercased()
        let query = url.query?.lowercased() ?? ""
        return blob.contains("oauth")
            || blob.contains("authorize")
            || blob.contains("/cas")
            || blob.contains("sso")
            || blob.contains("saml")
            || query.contains("ticket=")
            || query.contains("token=")
            || query.contains("code=")
    }

    static func isBareGraduateFrameset(_ url: URL?) -> Bool {
        guard isGraduateFrameset(url) else { return false }
        return (url?.query ?? "").isEmpty
    }

    static func resolvedSSOURL(_ raw: String, relativeTo base: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = URL(string: trimmed) ?? URL(string: trimmed, relativeTo: base)?.absoluteURL
        guard let url, hasConcreteHTTPURL(url), looksLikeSSOEntry(url) else { return nil }
        return url
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

import Foundation
@preconcurrency import WebKit
import Combine
import UIKit

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
    @Published private(set) var captureEngine = ""
    @Published private(set) var captureAttempt = 0

    let webView: WKWebView
    /// Popup created by `window.open` / `target=_blank` when the request has no concrete URL yet.
    @Published var popupWebView: WKWebView?
    private var credentials: SchoolCredentials?
    private var didClickMyTimetable = false
    /// Set only when the user taps 「进入研究生系统」 while not yet on appList.
    private var pendingGraduateTileClick = false
    /// IAM welcome/user-center → appList, at most once per session.
    private var didRedirectToAppList = false
    private var appListRedirectInFlight = false
    private var urlObservations: [NSKeyValueObservation] = []
    private let processPool = WKProcessPool()
    private let dataStore = WKWebsiteDataStore.nonPersistent()
    private let parser = ZgysyjyParser()

    static let desktopSafariUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.processPool = processPool
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
        captureEngine = ""
        captureAttempt = 0
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
        await applyAppListHash(in: webView)
        if await waitForAppList(in: webView, attempts: 10) { return }
        SafeLog.info("Hash did not stick; loading portal appList URL (not frameset)")
        loadSchoolPage(SchoolParser.portalAppListURL, in: webView)
        _ = await waitForAppList(in: webView, attempts: 10)
    }

    private func applyAppListHash(in webView: WKWebView) async {
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.goToAppList)
            let dict = Self.dictionary(from: raw)
            SafeLog.info("appList hash method=\(dict["method"] as? String ?? "")")
        } catch {
            SafeLog.error("appList hash script: \(error.localizedDescription)")
        }
    }

    /// Hash SPA can lag; wait until location has appList (and tiles if they appear).
    @discardableResult
    private func waitForAppList(in webView: WKWebView, attempts: Int) async -> Bool {
        for step in 0..<attempts {
            await syncURLFromPage(webView)
            let probe = await probeAppListTiles(from: webView)
            let hashReady = PortalNavigation.isAppList(currentURL ?? webView.url) || probe.hashReady
            if hashReady {
                if probe.hits > 0 || step >= attempts - 3 {
                    timetableHint = Self.appListSSOHint
                    phase = .readyToParse
                    SafeLog.info("Landed on portal appList tiles=\(probe.hits) step=\(step)")
                    return true
                }
            } else if PortalNavigation.isIAMPostLogin(currentURL ?? webView.url), step == 3 || step == 6 {
                await applyAppListHash(in: webView)
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
        await syncURLFromPage(webView)
        let ok = PortalNavigation.isAppList(currentURL ?? webView.url)
        if ok {
            timetableHint = Self.appListSSOHint
            phase = .readyToParse
        }
        return ok
    }

    private struct AppListProbe {
        var hashReady = false
        var hits = 0
    }

    private func probeAppListTiles(from webView: WKWebView) async -> AppListProbe {
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.detectAppListTiles)
            let dict = Self.dictionary(from: raw)
            return AppListProbe(
                hashReady: dict["hashReady"] as? Bool ?? false,
                hits: Self.intValue(dict["hits"])
            )
        } catch {
            SafeLog.error("appList probe: \(error.localizedDescription)")
            return AppListProbe()
        }
    }

    private func clickGraduateTile(from webView: WKWebView) async {
        pendingGraduateTileClick = false
        timetableHint = "正在点应用列表里的「研究生综合管理」，以保留门户登录态…"
        _ = await waitForAppList(in: webView, attempts: 6)
        for attempt in 0..<3 {
            do {
                let raw = try await webView.evaluateJavaScript(EmbeddedScripts.openGraduateTile)
                let dict = Self.dictionary(from: raw)
                let clicked = dict["clicked"] as? Bool ?? false
                let href = dict["href"] as? String ?? ""
                let method = dict["method"] as? String ?? ""
                let scanned = Self.intValue(dict["scanned"])
                let reason = dict["reason"] as? String ?? ""
                SafeLog.info("Graduate tile attempt=\(attempt + 1) clicked=\(clicked) method=\(method) scanned=\(scanned) reason=\(reason) hasHref=\(!href.isEmpty)")
                if let url = PortalNavigation.resolvedSSOURL(href, relativeTo: currentURL ?? webView.url) {
                    SafeLog.info("Loading discovered SSO host=\(url.host ?? "") path=\(url.path)")
                    loadSchoolPage(url, in: webView)
                    timetableHint = "已通过门户单点登录跳转。进入课表后点「录入课表」。"
                    return
                }
                if clicked {
                    timetableHint = "已尝试点开「研究生综合管理」。等跳转完成后打开「我的课表」，再点「录入课表」。"
                    return
                }
            } catch {
                SafeLog.error("Graduate tile script attempt=\(attempt + 1): \(error.localizedDescription)")
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
        }
        markSSOBlocked(Self.tileClickFailedHint)
        SafeLog.info("Graduate tile click not found after retries")
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
        guard PortalNavigation.isGraduateFrameset(currentURL ?? webView.url)
            || PortalNavigation.isGraduateHost(currentURL ?? webView.url) else { return }
        applyGraduatePageZoom(on: webView)
        if !didClickMyTimetable {
            for attempt in 0..<4 {
                do {
                    let raw = try await webView.evaluateJavaScript(EmbeddedScripts.openMyTimetable)
                    let dict = Self.dictionary(from: raw)
                    if dict["clicked"] as? Bool == true {
                        didClickMyTimetable = true
                        timetableHint = "已尝试打开「我的课表」。左侧已尽量滚入视野；确认高亮且出现周课表后再点「录入课表」。"
                        SafeLog.info("Clicked 我的课表 attempt=\(attempt + 1)")
                        break
                    }
                    SafeLog.info("我的课表 not found attempt=\(attempt + 1)")
                } catch {
                    SafeLog.error("我的课表 script attempt=\(attempt + 1): \(error.localizedDescription)")
                }
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
            if !didClickMyTimetable {
                didClickMyTimetable = true
                timetableHint = "请点左侧「我的课表」（已尽量滚入视野），再点「录入课表」。"
                SafeLog.info("我的课表 click not found; ask user")
            }
        }
        await revealMyTimetableMenu(from: webView)
        await revealWeeklyGrid(from: webView)
    }

    private func applyGraduatePageZoom(on webView: WKWebView) {
        if abs(webView.pageZoom - 1.15) > 0.01 {
            webView.pageZoom = 1.15
        }
    }

    @discardableResult
    private func revealMyTimetableMenu(from webView: WKWebView) async -> Bool {
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.revealMyTimetable)
            let dict = Self.dictionary(from: raw)
            let focused = dict["focused"] as? Bool ?? false
            SafeLog.info("Focus 我的课表 focused=\(focused)")
            return focused
        } catch {
            SafeLog.error("Focus 我的课表: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    private func revealWeeklyGrid(from webView: WKWebView) async -> Bool {
        do {
            let raw = try await webView.evaluateJavaScript(EmbeddedScripts.revealWeeklyGrid)
            let dict = Self.dictionary(from: raw)
            let found = dict["found"] as? Bool ?? false
            SafeLog.info("Reveal weekly grid found=\(found) score=\(Self.intValue(dict["score"]))")
            return found
        } catch {
            SafeLog.error("Reveal weekly grid: \(error.localizedDescription)")
            return false
        }
    }

    func userTappedParseCurrentPage() async {
        await captureVisibleSchedule()
    }

    /// Primary: HTML/DOM tables in frameset children. Snapshot vision is a one-shot fallback.
    /// Never auto-writes.
    func captureVisibleSchedule() async {
        phase = .parsing
        captureEngine = ""
        captureAttempt = 1
        timetableHint = "正在从网页表格提取课表。识别后需你核对，不会自动写入。"
        await revealMyTimetableMenu(from: activeWebView)
        await revealWeeklyGrid(from: activeWebView)
        try? await Task.sleep(nanoseconds: 280_000_000)

        let payload: ExtractedPage
        do {
            payload = try await extractScheduleDOM()
        } catch {
            SafeLog.error("DOM extract: \(error.localizedDescription)")
            await finishCaptureWithOptionalSnapshotFallback(
                reason: "无法读取课表网页：\(error.localizedDescription)",
                loginWall: false
            )
            return
        }

        let blob = payload.html + (payload.innerText ?? "")
        if Self.isLoginWallText(blob) {
            let message = Self.loginWallHint
            phase = .failed(message)
            timetableHint = message
            SafeLog.info("Portal HTML extract hit login wall")
            return
        }

        var parsed = parser.parse(html: payload.html, pageURL: payload.url, innerText: payload.innerText)
        parsed.classes = WeeklyGridOCRParser.mergeAndDedupe(parsed.classes)
        var engine = "HTML 周课表"

        if shouldTryTextCleanup(parsed, pageText: payload.innerText ?? blob) {
            if let cleaned = await textOnlyLLMDrafts(from: payload.innerText ?? payload.html) {
                let merged = WeeklyGridOCRParser.mergeAndDedupe(parsed.classes + cleaned)
                if !merged.isEmpty {
                    parsed.classes = merged
                    engine = "HTML + 文本整理"
                }
            }
        }

        if !parsed.classes.isEmpty, !looksCollapsedToMorningBand(parsed.classes, pageText: payload.innerText ?? blob) {
            finishCaptureSuccess(parsed, engine: engine)
            return
        }
        if !parsed.classes.isEmpty {
            finishCaptureSuccess(parsed, engine: engine)
            return
        }

        await finishCaptureWithOptionalSnapshotFallback(
            reason: parsed.blocker ?? "网页表格未解析到课程。请确认已打开「我的课表」，或改用导入页截图。",
            loginWall: false
        )
    }

    private func extractScheduleDOM() async throws -> ExtractedPage {
        do {
            let raw = try await activeWebView.evaluateJavaScript(EmbeddedScripts.extractScheduleTables)
            let tables = decodeExtract(raw)
            if !tables.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SafeLog.info("Extracted schedule tables")
                return tables
            }
        } catch {
            SafeLog.error("extractScheduleTables: \(error.localizedDescription)")
        }
        let raw = try await activeWebView.evaluateJavaScript(EmbeddedScripts.extractPage)
        return decodeExtract(raw)
    }

    private func shouldTryTextCleanup(_ parsed: ParseResult, pageText: String) -> Bool {
        if parsed.classes.isEmpty { return true }
        return looksCollapsedToMorningBand(parsed.classes, pageText: pageText)
    }

    private func looksCollapsedToMorningBand(_ drafts: [ParsedClassDraft], pageText: String) -> Bool {
        guard drafts.count >= 2 else { return false }
        let starts = Set(drafts.map(\.startMinutes))
        let onlyMorning = starts.count == 1 && starts.contains(9 * 60)
        let pageHasOtherBands = pageText.contains("下午课") || pageText.contains("晚上课")
            || pageText.contains("13:30") || pageText.contains("19:00")
        return onlyMorning && pageHasOtherBands
    }

    private func textOnlyLLMDrafts(from text: String) async -> [ParsedClassDraft]? {
        do {
            guard let config = try CredentialsStore.shared.loadAIConfiguration(), config.isUsable else {
                return nil
            }
            let engine = MultimodalAIEngine(configuration: config)
            let json = try await engine.recognizeTimetable(plainText: text)
            var drafts = TimetableHeuristics.drafts(fromStructuredJSON: json)
            if drafts.isEmpty {
                drafts = TimetableHeuristics.drafts(fromPlainText: json)
            }
            return WeeklyGridOCRParser.mergeAndDedupe(drafts)
        } catch {
            SafeLog.error("Text-only timetable cleanup: \(error.localizedDescription)")
            return nil
        }
    }

    private func finishCaptureSuccess(_ parsed: ParseResult, engine: String) {
        captureEngine = engine
        let result = ParseResult(
            classes: parsed.classes,
            sourceDescription: "\(parsed.sourceDescription) portal-html",
            blocker: nil,
            rawExcerpt: parsed.rawExcerpt
        )
        phase = .parsed(result)
        timetableHint = "请核对清单后再写入。识别不会自动改本机课表。"
        SafeLog.info("Portal HTML capture classes=\(parsed.classes.count) engine=\(engine)")
    }

    private func finishCaptureWithOptionalSnapshotFallback(reason: String, loginWall: Bool) async {
        if loginWall {
            phase = .failed(reason)
            timetableHint = reason
            return
        }
        captureAttempt = 2
        timetableHint = "网页表格不够用，改用一次页面截图识别…"
        do {
            let images = try await snapshotScheduleViews()
            let outcome = try await ScreenshotImporter().importImages(images)
            let merged = WeeklyGridOCRParser.mergeAndDedupe(outcome.result.classes)
            if !merged.isEmpty {
                captureEngine = "截图兜底 \(outcome.engine)"
                phase = .parsed(
                    ParseResult(
                        classes: merged,
                        sourceDescription: "\(outcome.result.sourceDescription) portal-snapshot-fallback",
                        blocker: nil,
                        rawExcerpt: outcome.result.rawExcerpt
                    )
                )
                timetableHint = "请核对清单后再写入。这次用了截图兜底，优先仍应以网页课表为准。"
                SafeLog.info("Portal snapshot fallback classes=\(merged.count)")
                return
            }
        } catch {
            SafeLog.error("Snapshot fallback: \(error.localizedDescription)")
        }
        let message = reason + " 也可关闭后到「导入」用课表截图。"
        phase = .failed(message)
        timetableHint = message
    }

    private static func isLoginWallText(_ text: String) -> Bool {
        text.contains("请登录") || text.contains("数据处理出现错误")
    }

    private func snapshotScheduleViews() async throws -> [UIImage] {
        var images: [UIImage] = []
        images.append(try await snapshotVisible())
        _ = try? await activeWebView.evaluateJavaScript(EmbeddedScripts.scrollWeeklyGridDown)
        try? await Task.sleep(nanoseconds: 280_000_000)
        if let extra = try? await snapshotVisible() {
            images.append(extra)
        }
        return images
    }

    private func snapshotVisible() async throws -> UIImage {
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true
        let view = activeWebView
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UIImage, Error>) in
            view.takeSnapshot(with: config, completionHandler: { image, error in
                if let image {
                    continuation.resume(returning: image)
                    return
                }
                continuation.resume(throwing: error ?? ScreenshotImporterError.invalidImage)
            })
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

    private func decodeExtract(_ raw: Any?) -> ExtractedPage {
        let dict = Self.dictionary(from: raw)
        let url = (dict["url"] as? String).flatMap(URL.init(string:))
        let html = dict["html"] as? String ?? ""
        let text = dict["innerText"] as? String
        return ExtractedPage(url: url, html: html, innerText: text)
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

    private static func intValue(_ raw: Any?) -> Int {
        if let n = raw as? Int { return n }
        if let n = raw as? NSNumber { return n.intValue }
        if let d = raw as? Double { return Int(d) }
        return 0
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
        if let url, url.host?.lowercased().contains("wxt.zgysyjy.org.cn") == true {
            SafeLog.info("wxt hop port=\(url.port.map(String.init) ?? "443") path=\(url.path) hasQuery=\(url.query?.isEmpty == false)")
        }
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
        if case .parsing = phase { return }
        if PortalNavigation.isGraduateFrameset(webView.url) || PortalNavigation.isGraduateHost(webView.url) {
            phase = .readyToParse
            applyGraduatePageZoom(on: webView)
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
            switch phase {
            case .parsed, .parsing:
                break
            default:
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
                SafeLog.info("window.open same WebView host=\(url.host ?? "") port=\(url.port.map(String.init) ?? "-") path=\(url.path)")
                webView.load(navigationAction.request)
            } else {
                SafeLog.info("Blocked popup host: \(url.host ?? url.absoluteString)")
            }
            return nil
        }

        configuration.websiteDataStore = dataStore
        configuration.processPool = processPool
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let child = WKWebView(frame: webView.bounds, configuration: configuration)
        child.customUserAgent = Self.desktopSafariUA
        child.allowsBackForwardNavigationGestures = true
        child.navigationDelegate = self
        child.uiDelegate = self
        popupWebView = child
        observeURL(of: child)
        SafeLog.info("Created in-sheet child WebView for window.open blank")
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

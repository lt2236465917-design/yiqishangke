import Foundation

/// School-specific parser for 中国艺术研究院 (zgysyjy). Post-login timetable URL is UNVERIFIED.
struct ZgysyjyParser: SchoolParsing {
    static let loginURL = URL(string: "https://iam.zgysyjy.org.cn/am/mLogin/login.html")!

    /// Candidate paths after IAM — hypotheses only, not confirmed against a live session.
    static let candidateTimetableHints: [String] = [
        "wdkb", "xskb", "kbcx", "timetable", "courseTable", "course-table",
        "kbgl", "pygc", "wdkc", "mycourse", "student/course", "课表", "我的课表"
    ]

    func parse(html: String, pageURL: URL?, innerText: String?) -> ParseResult {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (innerText ?? "").isEmpty {
            return ParseResult(
                classes: [],
                sourceDescription: "zgysyjy-stub",
                blocker: SchoolParserError.emptyPage.localizedDescription,
                rawExcerpt: nil
            )
        }

        var drafts: [ParsedClassDraft] = []

        if let jsonDrafts = extractEmbeddedJSON(from: html) {
            drafts.append(contentsOf: jsonDrafts)
        }
        drafts.append(contentsOf: parseHTMLTables(html))
        if let innerText {
            drafts.append(contentsOf: TimetableHeuristics.drafts(fromPlainText: innerText))
        }
        drafts.append(contentsOf: TimetableHeuristics.drafts(fromPlainText: stripTags(html)))
        drafts = TimetableHeuristics.unique(drafts)

        let looksLikeTimetable = pageLooksLikeTimetable(html: html, url: pageURL, text: innerText)
        var blocker: String?
        if drafts.isEmpty {
            if looksLikeTimetable {
                blocker = SchoolParserError.noTableFound.localizedDescription
            } else {
                blocker = """
                课后课表地址未核实（IAM 之后的页面无法从本环境打开）。\
                请在登录后自行进入「我的课表 / 课表查询」，再点「解析本页」。\
                若仍失败，请改用截图导入。
                """
            }
        }

        let excerpt = String((innerText ?? stripTags(html)).prefix(400))
        return ParseResult(
            classes: drafts,
            sourceDescription: "zgysyjy-stub \(pageURL?.absoluteString ?? "no-url")",
            blocker: blocker,
            rawExcerpt: excerpt
        )
    }

    func pageLooksLikeTimetable(html: String, url: URL?, text: String?) -> Bool {
        let hay = ((url?.absoluteString ?? "") + html + (text ?? "")).lowercased()
        return Self.candidateTimetableHints.contains { hay.contains($0.lowercased()) }
    }

    private func extractEmbeddedJSON(from html: String) -> [ParsedClassDraft]? {
        let pattern = #"<script[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var drafts: [ParsedClassDraft] = []
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let body = ns.substring(with: match.range(at: 1))
            for snippet in JSONSnippets.extract(from: body) {
                if let object = try? JSONSerialization.jsonObject(with: Data(snippet.utf8)) {
                    drafts.append(contentsOf: TimetableHeuristics.drafts(fromJSONObject: object))
                }
            }
        }
        return drafts.isEmpty ? nil : drafts
    }

    private func parseHTMLTables(_ html: String) -> [ParsedClassDraft] {
        var drafts: [ParsedClassDraft] = []
        let rowPattern = #"<tr[^>]*>([\s\S]*?)</tr>"#
        let cellPattern = #"<t[dh][^>]*>([\s\S]*?)</t[dh]>"#
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.caseInsensitive]),
              let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.caseInsensitive]) else {
            return []
        }
        let ns = html as NSString
        let rows = rowRegex.matches(in: html, range: NSRange(location: 0, length: ns.length))
        var headers: [String] = []
        for (index, row) in rows.enumerated() {
            let rowHTML = ns.substring(with: row.range(at: 1))
            let rowNS = rowHTML as NSString
            let cells = cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: rowNS.length))
                .map { stripTags(rowNS.substring(with: $0.range(at: 1))) }
            if index == 0 || cells.contains(where: { $0.contains("课程") || $0.contains("星期") }) {
                headers = cells
                continue
            }
            if cells.count >= 3 {
                let joined = zip(headers.isEmpty ? cells.map { _ in "" } : headers, cells)
                    .map { $0.isEmpty ? $1 : "\($0):\($1)" }
                    .joined(separator: " ")
                drafts.append(contentsOf: TimetableHeuristics.drafts(fromPlainText: joined))
                drafts.append(contentsOf: TimetableHeuristics.drafts(fromPlainText: cells.joined(separator: " ")))
            }
        }
        return drafts
    }

    private func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

private enum JSONSnippets {
    static func extract(from script: String) -> [String] {
        var snippets: [String] = []
        var i = script.startIndex
        while i < script.endIndex {
            if script[i] == "[" || script[i] == "{" {
                if let end = matchJSON(script, from: i) {
                    snippets.append(String(script[i...end]))
                    i = script.index(after: end)
                    continue
                }
            }
            i = script.index(after: i)
        }
        return snippets.filter { $0.count > 20 && $0.count < 800_000 }
    }

    private static func matchJSON(_ text: String, from start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escape = false
        var i = start
        let open = text[start]
        guard open == "{" || open == "[" else { return nil }
        while i < text.endIndex {
            let ch = text[i]
            if inString {
                if escape { escape = false }
                else if ch == "\\" { escape = true }
                else if ch == "\"" { inString = false }
            } else {
                if ch == "\"" { inString = true }
                else if ch == "{" || ch == "[" { depth += 1 }
                else if ch == "}" || ch == "]" {
                    depth -= 1
                    if depth == 0 { return i }
                }
            }
            i = text.index(after: i)
        }
        return nil
    }
}

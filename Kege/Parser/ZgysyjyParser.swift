import Foundation

/// School-specific parser for 中国艺术研究院 (zgysyjy).
struct ZgysyjyParser: SchoolParsing {
    static let loginURL = URL(string: "https://iam.zgysyjy.org.cn/am/mLogin/login.html")!
    static let portalAppListURL = URL(string: "https://iam.zgysyjy.org.cn/portal/#/appList")!
    /// Graduate management after SSO. Verified by user. This is a frameset shell, not the timetable page.
    static let graduateFramesetURL = URL(string: "https://wxt.zgysyjy.org.cn:7792/graduate/frameset.jsp")!

    /// TODO: Exact timetable submenu URL inside the graduate frameset is still unknown.
    /// Candidates only — do not treat as verified deep links.
    static let candidateTimetableHints: [String] = [
        "wdkb", "xskb", "kbcx", "timetable", "courseTable", "course-table",
        "kbgl", "pygc", "wdkc", "mycourse", "student/course",
        "课表", "我的课表", "课程表", "新学期课表", "frameset", "graduate"
    ]

    func parse(html: String, pageURL: URL?, innerText: String?) -> ParseResult {
        if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (innerText ?? "").isEmpty {
            return ParseResult(
                classes: [],
                sourceDescription: "zgysyjy-empty",
                blocker: SchoolParserError.emptyPage.localizedDescription,
                rawExcerpt: nil
            )
        }

        var drafts: [ParsedClassDraft] = []
        if let jsonDrafts = extractEmbeddedJSON(from: html) {
            drafts.append(contentsOf: jsonDrafts)
        }

        let tables = parseSchoolTables(html)
        drafts.append(contentsOf: tables.drafts)

        if tables.drafts.isEmpty {
            if let innerText {
                drafts.append(contentsOf: TimetableHeuristics.drafts(fromPlainText: innerText))
            }
            drafts.append(contentsOf: TimetableHeuristics.drafts(fromPlainText: stripTags(html)))
        }
        drafts = TimetableHeuristics.unique(drafts)

        let looksLikeTimetable = pageLooksLikeTimetable(html: html, url: pageURL, text: innerText)
        var blocker: String?
        if drafts.isEmpty {
            if (innerText ?? html).contains("请登录") || (innerText ?? html).contains("数据处理出现错误") {
                blocker = """
                研究生系统在要登录，说明没带上门户会话。请回到应用列表点「研究生综合管理」；直达裸开会丢登录态。仍失败请改用截图导入。
                """
            } else if looksLikeTimetable {
                blocker = SchoolParserError.noTableFound.localizedDescription
            } else if Self.isGraduateFrameset(pageURL) {
                blocker = """
                当前是研究生系统框架页（frameset.jsp），课表在子 frame。\
                请点左侧「我的课表」后再解析本页。课表子菜单准确 URL 尚未核实。
                """
            } else {
                blocker = """
                未识别到课表。请进入研究生系统后打开「我的课表」，再点「解析本页」。\
                课表子菜单 URL 未知。若仍失败请改用截图导入。
                """
            }
        }

        let excerpt = String((innerText ?? stripTags(html)).prefix(400))
        return ParseResult(
            classes: drafts,
            sourceDescription: "zgysyjy grid=\(tables.gridCount) list=\(tables.listCount) \(pageURL?.absoluteString ?? "no-url")",
            blocker: blocker,
            rawExcerpt: excerpt
        )
    }

    func pageLooksLikeTimetable(html: String, url: URL?, text: String?) -> Bool {
        let hay = html + (text ?? "")
        if looksLikeListTable(hay) || looksLikeWeeklyGrid(hay) { return true }
        if hay.contains("新学期课表") || hay.contains("上课时间、地点") { return true }
        if Self.isGraduateFrameset(url) { return false }
        let blob = ((url?.absoluteString ?? "") + hay).lowercased()
        return Self.candidateTimetableHints.contains { blob.contains($0.lowercased()) }
    }

    static func isGraduateFrameset(_ url: URL?) -> Bool {
        guard let url else { return false }
        let path = url.path.lowercased()
        return path.contains("/graduate/frameset.jsp") || path.hasSuffix("frameset.jsp")
    }

    static func isGraduateHost(_ url: URL?) -> Bool {
        url?.host?.lowercased().contains("wxt.zgysyjy.org.cn") == true
    }

    private func looksLikeListTable(_ text: String) -> Bool {
        text.contains("课程编号") && text.contains("课程名称") && text.contains("上课时间")
    }

    private func looksLikeWeeklyGrid(_ text: String) -> Bool {
        let hasDays = text.contains("周一") && text.contains("周日")
        let hasPeriod = text.contains("上午课") || text.contains("下午课")
        return hasDays && hasPeriod
    }

    private struct TableParse {
        var drafts: [ParsedClassDraft]
        var gridCount: Int
        var listCount: Int
    }

    private func parseSchoolTables(_ html: String) -> TableParse {
        var grid: [ParsedClassDraft] = []
        var list: [ParsedClassDraft] = []
        for table in HTMLTableSlice.tables(in: html) {
            if let weekly = parseWeeklyGrid(table), !weekly.isEmpty {
                grid.append(contentsOf: weekly)
                continue
            }
            if let rows = parseListTable(table), !rows.isEmpty {
                list.append(contentsOf: rows)
            }
        }
        return TableParse(
            drafts: mergeGridPreferred(grid, list: list),
            gridCount: grid.count,
            listCount: list.count
        )
    }

    /// Weekly grid wins on title+weekday (real clocks). List fills gaps and empty fields.
    private func mergeGridPreferred(_ grid: [ParsedClassDraft], list: [ParsedClassDraft]) -> [ParsedClassDraft] {
        var result = grid
        for extra in list {
            if let index = result.firstIndex(where: { $0.title == extra.title && $0.weekday == extra.weekday }) {
                if result[index].location.isEmpty { result[index].location = extra.location }
                if result[index].teacher.isEmpty { result[index].teacher = extra.teacher }
                if result[index].weeks == nil { result[index].weeks = extra.weeks }
                if result[index].notes.isEmpty { result[index].notes = extra.notes }
            } else {
                result.append(extra)
            }
        }
        return TimetableHeuristics.unique(result)
    }

    private func parseListTable(_ table: HTMLTableSlice) -> [ParsedClassDraft]? {
        guard let header = table.rows.first(where: isListHeader) else { return nil }
        let index = columnIndex(header)
        guard let titleIdx = index["title"], let meetingIdx = index["meeting"] else { return nil }

        var drafts: [ParsedClassDraft] = []
        for row in table.rows where !isListHeader(row) && row.count >= 3 {
            let title = cell(row, titleIdx)
            guard title.count >= 2 else { continue }
            if isUnselected(cell(row, index["selected"])) { continue }

            let meetings = ZgysyjyMeeting.parseCell(cell(row, meetingIdx))
            guard !meetings.isEmpty else { continue }

            let code = cell(row, index["code"])
            let klass = cell(row, index["class"])
            let credit = cell(row, index["credit"])
            let nature = cell(row, index["nature"])
            let notes = [code, klass, credit, nature].filter { !$0.isEmpty }.joined(separator: " · ")

            for meeting in meetings {
                drafts.append(
                    ParsedClassDraft(
                        title: title,
                        teacher: "",
                        location: meeting.room,
                        weekday: meeting.weekday,
                        startMinutes: meeting.start,
                        endMinutes: meeting.end,
                        weeks: meeting.weeks,
                        notes: notes
                    )
                )
            }
        }
        return drafts
    }

    private func isListHeader(_ row: [String]) -> Bool {
        let joined = row.joined()
        return joined.contains("课程编号") && joined.contains("课程名称") && joined.contains("上课时间")
    }

    private func isUnselected(_ value: String?) -> Bool {
        guard let value else { return false }
        let t = value.replacingOccurrences(of: " ", with: "")
        return t == "否" || t == "未选" || t == "未选中" || t.lowercased() == "n" || t.lowercased() == "false"
    }

    private func columnIndex(_ header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, raw) in header.enumerated() {
            let h = raw.replacingOccurrences(of: " ", with: "")
            if h.contains("课程编号") { map["code"] = i }
            else if h.contains("课程名称") { map["title"] = i }
            else if h.contains("班次") { map["class"] = i }
            else if h.contains("学分") { map["credit"] = i }
            else if h.contains("上课时间") { map["meeting"] = i }
            else if h.contains("选课性质") { map["nature"] = i }
            else if h.contains("是否选中") { map["selected"] = i }
        }
        return map
    }

    private func parseWeeklyGrid(_ table: HTMLTableSlice) -> [ParsedClassDraft]? {
        var dayColumns: [Int: ChinaWeekday] = [:]
        var numbered: [ParsedClassDraft] = []
        var bands: [ParsedClassDraft] = []
        for row in table.rows {
            let headerDays = weekdayColumns(row)
            if headerDays.count >= 3 {
                dayColumns = headerDays
                continue
            }
            guard !dayColumns.isEmpty else { continue }
            guard let minutes = rowPeriodMinutes(row) else { continue }
            let prefix = row.prefix(3).joined(separator: "\n")
            let kind = ZgysyjyMeeting.periodKind(from: prefix)
            for (col, weekday) in dayColumns {
                let text = cell(row, col)
                guard !text.isEmpty else { continue }
                if ChinaWeekday.parseColumnHeader(text) != nil && text.count <= 8 { continue }
                let parsed = ZgysyjyMeeting.parseGridCells(text, weekday: weekday, start: minutes.0, end: minutes.1)
                if kind?.isBand == true {
                    bands.append(contentsOf: parsed)
                } else {
                    numbered.append(contentsOf: parsed)
                }
            }
        }
        let drafts = WeeklyGridOCRParser.mergeAndDedupe(numbered.isEmpty ? bands : numbered)
        return drafts.isEmpty ? nil : drafts
    }

    private func weekdayColumns(_ row: [String]) -> [Int: ChinaWeekday] {
        var map: [Int: ChinaWeekday] = [:]
        for (i, raw) in row.enumerated() {
            let compact = raw.replacingOccurrences(of: " ", with: "")
            if let day = ChinaWeekday.parseColumnHeader(compact) {
                map[i] = day
            }
        }
        return map
    }

    private func rowPeriodMinutes(_ row: [String]) -> (Int, Int)? {
        let prefix = row.prefix(3).joined(separator: "\n")
        if let clock = ZgysyjyMeeting.parseClockRange(prefix) {
            return clock
        }
        if let kind = ZgysyjyMeeting.periodKind(from: prefix) {
            return kind.minutes
        }
        if let period = ZgysyjyMeeting.periodMinutes(from: prefix) {
            return period
        }
        return nil
    }

    private func cell(_ row: [String], _ index: Int?) -> String {
        guard let index, row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }
}

/// Flatten HTML tables, expanding rowspan/colspan so column indexes stay stable.
struct HTMLTableSlice {
    var rows: [[String]]

    static func tables(in html: String) -> [HTMLTableSlice] {
        extractTableHTML(html).compactMap { slice(from: $0) }
    }

    private static func extractTableHTML(_ html: String) -> [String] {
        var tables: [String] = []
        var search = html.startIndex
        while search < html.endIndex,
              let start = html.range(of: "<table", options: .caseInsensitive, range: search..<html.endIndex) {
            var depth = 0
            var i = start.lowerBound
            var end: String.Index?
            while i < html.endIndex {
                if html[i...].prefix(6).lowercased() == "<table" {
                    depth += 1
                    i = html.index(i, offsetBy: 6, limitedBy: html.endIndex) ?? html.endIndex
                    continue
                }
                if html[i...].prefix(8).lowercased() == "</table>" {
                    depth -= 1
                    if depth == 0 {
                        end = html.index(i, offsetBy: 8, limitedBy: html.endIndex) ?? html.endIndex
                        break
                    }
                    i = html.index(i, offsetBy: 8, limitedBy: html.endIndex) ?? html.endIndex
                    continue
                }
                i = html.index(after: i)
            }
            if let end {
                tables.append(String(html[start.lowerBound..<end]))
                search = end
            } else {
                break
            }
        }
        return tables
    }

    private static func slice(from tableHTML: String) -> HTMLTableSlice? {
        guard let rowRegex = try? NSRegularExpression(pattern: #"<tr[^>]*>([\s\S]*?)</tr>"#, options: [.caseInsensitive]),
              let cellRegex = try? NSRegularExpression(pattern: #"<t[dh]([^>]*)>([\s\S]*?)</t[dh]>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = tableHTML as NSString
        let rowMatches = rowRegex.matches(in: tableHTML, range: NSRange(location: 0, length: ns.length))
        var carry: [Int: (text: String, left: Int)] = [:]
        var rows: [[String]] = []
        for rowMatch in rowMatches {
            let rowHTML = ns.substring(with: rowMatch.range(at: 1))
            let rowNS = rowHTML as NSString
            let cells = cellRegex.matches(in: rowHTML, range: NSRange(location: 0, length: rowNS.length)).map { match -> (text: String, rowspan: Int, colspan: Int) in
                let attrs = rowNS.substring(with: match.range(at: 1))
                let inner = rowNS.substring(with: match.range(at: 2))
                return (cellText(inner), span(attrs, "rowspan"), span(attrs, "colspan"))
            }
            var col = 0
            var cellIndex = 0
            var output: [String] = []
            while cellIndex < cells.count || carry[col] != nil {
                if let held = carry[col], held.left > 0 {
                    output.append(held.text)
                    if held.left == 1 {
                        carry.removeValue(forKey: col)
                    } else {
                        carry[col] = (held.text, held.left - 1)
                    }
                    col += 1
                    continue
                }
                guard cellIndex < cells.count else { break }
                let cell = cells[cellIndex]
                cellIndex += 1
                for _ in 0..<max(1, cell.colspan) {
                    output.append(cell.text)
                    if cell.rowspan > 1 {
                        carry[col] = (cell.text, cell.rowspan - 1)
                    }
                    col += 1
                }
            }
            if !output.isEmpty {
                rows.append(output)
            }
        }
        return rows.isEmpty ? nil : HTMLTableSlice(rows: rows)
    }

    private static func span(_ attrs: String, _ name: String) -> Int {
        let pattern = #"\#(name)\s*=\s*["']?(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(match.range(at: 1), in: attrs),
              let value = Int(attrs[range]) else {
            return 1
        }
        return max(1, value)
    }

    private static func cellText(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</div>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[\t\f]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

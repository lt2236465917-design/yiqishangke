import Foundation

struct ParsedClassDraft: Equatable, Sendable {
    var title: String
    var teacher: String
    var location: String
    var weekday: ChinaWeekday
    var startMinutes: Int
    var endMinutes: Int
    var weeks: [Int]?
    var notes: String

    func asSession(source: ClassSource) -> ClassSession {
        ClassSession(
            title: title,
            teacher: teacher,
            location: location,
            weekday: weekday,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            weeks: weeks,
            notes: notes,
            source: source
        )
    }
}

struct ParseResult: Equatable, Sendable {
    var classes: [ParsedClassDraft]
    var sourceDescription: String
    var blocker: String?
    var rawExcerpt: String?

    var isEmpty: Bool { classes.isEmpty }
}

enum SchoolParserError: LocalizedError, Equatable {
    case timetableURLUnverified
    case noTableFound
    case emptyPage

    var errorDescription: String? {
        switch self {
        case .timetableURLUnverified:
            "课后登录课表地址尚未核实。请在 WebView 中手动进入课表页后点「解析本页」，或改用截图导入。"
        case .noTableFound:
            "当前页未识别出课表结构。"
        case .emptyPage:
            "页面内容为空。"
        }
    }
}

protocol SchoolParsing: Sendable {
    func parse(html: String, pageURL: URL?, innerText: String?) -> ParseResult
}

/// Heuristic extractor used by the zgysyjy stub and screenshot OCR/AI text.
enum TimetableHeuristics {
    /// zgysyjy weekly-grid clocks (user screenshots). Fallback when a row has 第N节 but no HH:MM.
    static let periodMap: [Int: (Int, Int)] = ZgysyjyMeeting.periodClock

    static func parseClock(_ text: String) -> Int? {
        let pattern = #"(\d{1,2})[:：点时](\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hRange = Range(match.range(at: 1), in: text),
              let mRange = Range(match.range(at: 2), in: text),
              let h = Int(text[hRange]), let m = Int(text[mRange]) else {
            return nil
        }
        return ClassSession.minutes(hour: h, minute: m)
    }

    static func parseClockRange(_ text: String) -> (Int, Int)? {
        let pattern = #"(\d{1,2})[:：](\d{2})\s*[-–—~至到]{1,2}\s*(\d{1,2})[:：](\d{2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r1 = Range(match.range(at: 1), in: text),
              let r2 = Range(match.range(at: 2), in: text),
              let r3 = Range(match.range(at: 3), in: text),
              let r4 = Range(match.range(at: 4), in: text),
              let h1 = Int(text[r1]), let m1 = Int(text[r2]),
              let h2 = Int(text[r3]), let m2 = Int(text[r4]) else {
            return nil
        }
        return (ClassSession.minutes(hour: h1, minute: m1), ClassSession.minutes(hour: h2, minute: m2))
    }

    static func parsePeriods(_ text: String) -> (Int, Int)? {
        let pattern = #"第?\s*(\d{1,2})\s*[-–—~到至]\s*(\d{1,2})\s*节"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text),
           let b = Range(match.range(at: 2), in: text),
           let start = Int(text[a]), let end = Int(text[b]) {
            return (start, end)
        }
        let single = #"第?\s*(\d{1,2})\s*节"#
        if let regex = try? NSRegularExpression(pattern: single),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text),
           let n = Int(text[a]) {
            return (n, n)
        }
        return nil
    }

    static func minutesForPeriods(start: Int, end: Int) -> (Int, Int)? {
        guard let s = periodMap[start], let e = periodMap[end] else { return nil }
        return (s.0, e.1)
    }

    static func parseWeeks(_ text: String) -> [Int]? {
        // 1-16周, 1-8周, 单周, 双周, 1,3,5周
        if text.contains("单周") { return Array(stride(from: 1, through: 20, by: 2)) }
        if text.contains("双周") { return Array(stride(from: 2, through: 20, by: 2)) }
        let rangePat = #"(\d{1,2})\s*[-–—~到至]\s*(\d{1,2})\s*周"#
        if let regex = try? NSRegularExpression(pattern: rangePat),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text),
           let b = Range(match.range(at: 2), in: text),
           let s = Int(text[a]), let e = Int(text[b]), s <= e {
            return Array(s...e)
        }
        let listPat = #"((?:\d{1,2}[、,，/])+?\d{1,2})\s*周"#
        if let regex = try? NSRegularExpression(pattern: listPat),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let a = Range(match.range(at: 1), in: text) {
            let nums = String(text[a]).split { ",，、/".contains($0) }.compactMap { Int($0) }
            return nums.isEmpty ? nil : nums
        }
        return nil
    }

    static func drafts(fromPlainText text: String) -> [ParsedClassDraft] {
        let lines = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var drafts: [ParsedClassDraft] = []
        var currentWeekday: ChinaWeekday?

        for line in lines {
            if let day = ChinaWeekday.parse(from: line), line.count <= 8 {
                currentWeekday = day
            }

            let weekday = ChinaWeekday.parse(from: line) ?? currentWeekday
            let range = parseClockRange(line)
            let periods = parsePeriods(line)
            let minutes = range ?? periods.flatMap { minutesForPeriods(start: $0.0, end: $0.1) }
            guard let weekday, let minutes else { continue }

            let title = extractTitle(from: line)
            guard title.count >= 2 else { continue }

            drafts.append(
                ParsedClassDraft(
                    title: title,
                    teacher: extractTeacher(from: line),
                    location: extractLocation(from: line),
                    weekday: weekday,
                    startMinutes: minutes.0,
                    endMinutes: minutes.1,
                    weeks: parseWeeks(line),
                    notes: ""
                )
            )
        }
        return unique(drafts)
    }

    static func drafts(fromStructuredJSON text: String) -> [ParsedClassDraft] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        if let array = object as? [Any] {
            return unique(drafts(fromJSONObject: array) + array.compactMap(draftFromFlexibleNode))
        }
        if let dict = object as? [String: Any] {
            for key in ["classes", "courses", "sessions", "items", "data"] {
                if let array = dict[key] as? [Any] {
                    return unique(array.compactMap(draftFromFlexibleNode))
                }
            }
            if let one = draftFromFlexibleNode(dict) {
                return [one]
            }
        }
        return unique(drafts(fromJSONObject: object))
    }

    private static func draftFromFlexibleNode(_ any: Any) -> ParsedClassDraft? {
        guard let node = any as? [String: Any] else { return nil }
        func string(_ keys: [String]) -> String? {
            for key in keys {
                if let value = node[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }
        func int(_ keys: [String]) -> Int? {
            for key in keys {
                if let value = node[key] as? Int { return value }
                if let value = node[key] as? String, let n = Int(value) { return n }
            }
            return nil
        }
        let title = string(["title", "course", "courseName", "name", "kcmc"])
        guard let title, title.count >= 2, !title.contains("虚拟教室") else { return nil }

        let weekday: ChinaWeekday?
        if let raw = string(["weekday", "weekDay", "day", "xq"]) {
            weekday = ChinaWeekday.parseColumnHeader(raw) ?? ChinaWeekday.parse(from: raw)
        } else if let n = int(["weekday", "weekDay", "day"]) {
            weekday = ChinaWeekday(rawValue: n == 0 ? 7 : n)
        } else {
            weekday = nil
        }
        guard let weekday else { return nil }

        var start = 0
        var end = 0
        if let startText = string(["start", "startTime", "begin"]),
           let endText = string(["end", "endTime"]),
           let s = parseClock(startText),
           let e = parseClock(endText) {
            start = s
            end = e
        } else if let range = string(["time", "clock"]).flatMap(parseClockRange) {
            start = range.0
            end = range.1
        } else if let period = string(["period", "periodLabel", "section", "jc"]),
                  let kind = ZgysyjyMeeting.periodKind(from: period) {
            start = kind.minutes.0
            end = kind.minutes.1
        } else {
            return nil
        }
        guard end > start else { return nil }

        var weeks: [Int]?
        if let list = node["weeks"] as? [Int] {
            weeks = list
        } else if let list = node["weeks"] as? [Any] {
            weeks = list.compactMap { $0 as? Int }
        } else if let text = string(["weeks", "week", "zcd"]) {
            weeks = parseWeeks(text.contains("周") ? text : "\(text)周") ?? ZgysyjyMeeting.parseWeeksPrefix(text)
        }

        let room = string(["location", "room", "place", "classroom"]) ?? ""
        let campus = string(["campus"]) ?? ""
        let location = [room, campus].filter { !$0.isEmpty }.joined(separator: " ")

        return ParsedClassDraft(
            title: title,
            teacher: string(["teacher", "teacherName", "jsxm"]) ?? "",
            location: location,
            weekday: weekday,
            startMinutes: start,
            endMinutes: end,
            weeks: weeks,
            notes: string(["notes", "remark", "periodLabel"]) ?? ""
        )
    }

    static func drafts(fromJSONObject object: Any) -> [ParsedClassDraft] {
        var nodes: [[String: Any]] = []
        collectDictionaries(object, into: &nodes)
        var drafts: [ParsedClassDraft] = []
        for node in nodes {
            if let draft = draft(fromJSON: node) {
                drafts.append(draft)
            }
        }
        return unique(drafts)
    }

    private static let cjkAndLetters: CharacterSet = {
        let cjk = CharacterSet(charactersIn: Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!)
        return cjk.union(.letters)
    }()

    static func unique(_ drafts: [ParsedClassDraft]) -> [ParsedClassDraft] {
        var seen = Set<String>()
        return drafts.filter { draft in
            let key = "\(draft.title)|\(draft.weekday.rawValue)|\(draft.startMinutes)|\(draft.endMinutes)|\(draft.location)"
            return seen.insert(key).inserted
        }
    }

    private static func draft(fromJSON node: [String: Any]) -> ParsedClassDraft? {
        func string(_ keys: [String]) -> String? {
            for key in keys {
                if let value = node[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                    return value.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return nil
        }
        func int(_ keys: [String]) -> Int? {
            for key in keys {
                if let value = node[key] as? Int { return value }
                if let value = node[key] as? String, let n = Int(value) { return n }
            }
            return nil
        }

        let title = string(["kcmc", "courseName", "course", "title", "name", "kcm", "kc"])
        guard let title, title.count >= 2 else { return nil }

        let weekdayRaw = string(["xqjmc", "weekday", "weekDay", "xq", "day"]) ?? int(["xqj", "week", "dayOfWeek"]).map(String.init)
        let weekday = weekdayRaw.flatMap(ChinaWeekday.parse)
            ?? int(["xqj", "dayOfWeek"]).flatMap { ChinaWeekday(rawValue: $0 == 0 ? 7 : $0) }
        guard let weekday else { return nil }

        var start = 0
        var end = 0
        if let rangeText = string(["kcsj", "time", "sksj", "courseTime"]), let range = parseClockRange(rangeText) {
            start = range.0
            end = range.1
        } else if let periodText = string(["jcs", "jc", "period"]),
                  let periods = parsePeriods(periodText),
                  let minutes = minutesForPeriods(start: periods.0, end: periods.1) {
            start = minutes.0
            end = minutes.1
        } else if let a = int(["startPeriod", "beginSection"]),
                  let b = int(["endPeriod", "endSection"]),
                  let minutes = minutesForPeriods(start: a, end: b) {
            start = minutes.0
            end = minutes.1
        } else {
            return nil
        }

        return ParsedClassDraft(
            title: title,
            teacher: string(["xm", "jgxm", "teacher", "teacherName", "jsxm"]) ?? "",
            location: string(["cdmc", "classroom", "place", "location", "skdd", "room"]) ?? "",
            weekday: weekday,
            startMinutes: start,
            endMinutes: end,
            weeks: string(["zcd", "weeks", "qsjsz"]).flatMap(parseWeeks),
            notes: string(["notes", "remark", "bz"]) ?? ""
        )
    }

    private static func collectDictionaries(_ any: Any, into nodes: inout [[String: Any]]) {
        if let dict = any as? [String: Any] {
            nodes.append(dict)
            for value in dict.values { collectDictionaries(value, into: &nodes) }
        } else if let array = any as? [Any] {
            for value in array { collectDictionaries(value, into: &nodes) }
        }
    }

    private static func extractTitle(from line: String) -> String {
        var t = line
        for day in ChinaWeekday.allCases {
            t = t.replacingOccurrences(of: day.shortLabel, with: " ")
            t = t.replacingOccurrences(of: day.fullLabel, with: " ")
        }
        t = t.replacingOccurrences(of: #"\d{1,2}[:：]\d{2}(?:\s*[-–—~至到]\s*\d{1,2}[:：]\d{2})?"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"第?\d{1,2}(?:\s*[-–—~到至]\s*\d{1,2})?\s*节"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\d{1,2}(?:\s*[-–—~到至]\s*\d{1,2})?\s*周"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(教室|地点|教师|老师)[:：]?\S*"#, with: " ", options: .regularExpression)
        let parts = t.split(whereSeparator: { $0.isWhitespace || $0 == "|" || $0 == "｜" || $0 == "·" })
            .map(String.init)
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: Self.cjkAndLetters) != nil }
        return parts.first ?? t.trimmingCharacters(in: .whitespaces)
    }

    private static func extractTeacher(from line: String) -> String {
        let pattern = #"(?:教师|老师|授课)[:：]?\s*([\u{4e00}-\u{9fff}A-Za-z]{2,8})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return "" }
        return String(line[range])
    }

    private static func extractLocation(from line: String) -> String {
        let pattern = #"(?:教室|地点|场地|授课地点)[:：]?\s*(\S{2,20})"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            return String(line[range])
        }
        let room = #"(教学楼|实验楼|排练厅|琴房|工作室|报告厅)\S{0,12}"#
        if let regex = try? NSRegularExpression(pattern: room),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range, in: line) {
            return String(line[range])
        }
        return ""
    }
}

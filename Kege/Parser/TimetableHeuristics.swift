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
    var timePending: Bool = false

    func asSession(source: ClassSource) -> ClassSession? {
        if timePending { return nil }
        guard endMinutes > startMinutes else { return nil }
        return ClassSession(
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
            "课后登录课表地址尚未核实。请在 WebView 中手动进入课表页后点「录入课表」，或改用截图导入。"
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
        let flexible = draftsFromFlexibleRoot(object)
        if !flexible.isEmpty {
            return unique(flexible)
        }
        return unique(drafts(fromJSONObject: object))
    }

    private static func draftsFromFlexibleRoot(_ object: Any) -> [ParsedClassDraft] {
        if let array = anyItems(object) {
            return array.flatMap(draftsFromFlexibleNode)
        }
        guard let dict = object as? [String: Any] else { return [] }
        var drafts: [ParsedClassDraft] = []
        if let pending = anyItems(dict["pending"]) {
            drafts.append(contentsOf: pending.compactMap(pendingDraft(from:)))
        }
        if let scheduled = anyItems(dict["scheduled"]) {
            drafts.append(contentsOf: scheduled.flatMap(draftsFromFlexibleNode))
        }
        for key in ["classes", "courses", "sessions", "items", "data"] {
            if let array = anyItems(dict[key]) {
                drafts.append(contentsOf: array.flatMap(draftsFromFlexibleNode))
            }
        }
        if drafts.isEmpty {
            drafts.append(contentsOf: draftsFromFlexibleNode(dict))
        }
        return drafts
    }

    private static func anyItems(_ raw: Any?) -> [Any]? {
        if let arr = raw as? [Any] { return arr }
        if let arr = raw as? NSArray { return arr.map { $0 as Any } }
        return nil
    }

    private static func draftsFromFlexibleNode(_ any: Any) -> [ParsedClassDraft] {
        guard let node = any as? [String: Any] else { return [] }
        if let meetings = anyItems(node["meetings"]) ?? anyItems(node["slots"]) ?? anyItems(node["times"]),
           !meetings.isEmpty {
            let title = stringValue(node, ["title", "course", "courseName", "name", "kcmc"]) ?? ""
            return meetings.flatMap { item -> [ParsedClassDraft] in
                if var dict = item as? [String: Any] {
                    if dict["title"] == nil { dict["title"] = title }
                    return draftsFromFlexibleNode(dict)
                }
                return []
            }
        }
        if isPendingNode(node) {
            if let pending = pendingDraft(from: node) { return [pending] }
            return []
        }
        if let one = scheduledDraft(from: node) {
            return [one]
        }
        return []
    }

    private static func isPendingNode(_ node: [String: Any]) -> Bool {
        if node["timePending"] as? Bool == true { return true }
        if node["pending"] as? Bool == true { return true }
        if node["unscheduled"] as? Bool == true { return true }
        let blob = [
            stringValue(node, ["reason", "status", "notes", "remark", "meeting", "sourceLine", "line", "raw"]) ?? "",
            stringValue(node, ["title", "course", "name"]) ?? ""
        ].joined(separator: " ")
        if ZgysyjyMeeting.isPendingMeeting(blob, title: stringValue(node, ["title", "course", "name"]) ?? "") {
            let hasClock = stringValue(node, ["startTime", "start", "begin"]) != nil
                || stringValue(node, ["sourceLine", "line", "meeting", "raw"]).flatMap(ZgysyjyMeeting.parseLine) != nil
            return !hasClock
        }
        return false
    }

    private static func pendingDraft(from any: Any) -> ParsedClassDraft? {
        guard let node = any as? [String: Any] else { return nil }
        let title = stringValue(node, ["title", "course", "courseName", "name", "kcmc"]) ?? ""
        guard title.count >= 2 else { return nil }
        return pendingDraft(
            title: title,
            teacher: stringValue(node, ["teacher", "teacherName", "jsxm"]) ?? "",
            notes: stringValue(node, ["reason", "notes", "remark", "credit"]) ?? "时间、地点待定"
        )
    }

    static func pendingDraft(title: String, teacher: String, notes: String) -> ParsedClassDraft {
        ParsedClassDraft(
            title: title,
            teacher: teacher,
            location: "",
            weekday: .monday,
            startMinutes: 0,
            endMinutes: 0,
            weeks: nil,
            notes: notes.isEmpty ? "时间、地点待定" : notes,
            timePending: true
        )
    }

    private static func scheduledDraft(from node: [String: Any]) -> ParsedClassDraft? {
        let title = stringValue(node, ["title", "course", "courseName", "name", "kcmc"])
        guard let title, title.count >= 2, !title.contains("虚拟教室") else { return nil }

        if let line = stringValue(node, ["sourceLine", "line", "meeting", "raw"]),
           let parsed = ZgysyjyMeeting.parseLine(line) {
            return ParsedClassDraft(
                title: title,
                teacher: stringValue(node, ["teacher", "teacherName", "jsxm"]) ?? "",
                location: parsed.room,
                weekday: parsed.weekday,
                startMinutes: parsed.start,
                endMinutes: parsed.end,
                weeks: parsed.weeks,
                notes: stringValue(node, ["notes", "remark", "periodLabel", "credit"]) ?? "",
                timePending: false
            )
        }

        let weekday: ChinaWeekday?
        if let raw = stringValue(node, ["weekday", "weekDay", "day", "xq"]) {
            weekday = ChinaWeekday.parseColumnHeader(raw) ?? ChinaWeekday.parse(from: raw)
        } else if let n = intValue(node, ["weekday", "weekDay", "day"]) {
            weekday = ChinaWeekday(rawValue: n == 0 ? 7 : n)
        } else {
            weekday = nil
        }
        guard let weekday else { return nil }

        let periodLabel = stringValue(node, ["periodLabel", "period", "section", "jc"]) ?? ""
        var start = 0
        var end = 0
        if let startText = stringValue(node, ["start", "startTime", "begin"]),
           let endText = stringValue(node, ["end", "endTime"]),
           let s = parseClock(startText),
           let e = parseClock(endText) {
            start = s
            end = e
        } else if let range = stringValue(node, ["time", "clock"]).flatMap(parseClockRange) {
            start = range.0
            end = range.1
        } else if let kind = ZgysyjyMeeting.periodKind(from: periodLabel) {
            start = kind.minutes.0
            end = kind.minutes.1
        } else {
            return nil
        }
        if let kind = ZgysyjyMeeting.periodKind(from: periodLabel), kind.isBand,
           start == 9 * 60, end == 12 * 60, kind != .bandMorning {
            start = kind.minutes.0
            end = kind.minutes.1
        }
        guard end > start else { return nil }

        var weeks: [Int]?
        if let list = node["weeks"] as? [Int] {
            weeks = list
        } else if let list = anyItems(node["weeks"]) {
            weeks = list.compactMap { $0 as? Int }
        } else if let text = stringValue(node, ["weeks", "week", "zcd"]) {
            weeks = parseWeeks(text.contains("周") ? text : "\(text)周") ?? ZgysyjyMeeting.parseWeeksPrefix(text)
        }

        let room = stringValue(node, ["location", "room", "place", "classroom"]) ?? ""
        let campus = stringValue(node, ["campus"]) ?? ""
        let location = [room, campus].filter { !$0.isEmpty }.joined(separator: " ")
        let notes = [periodLabel, stringValue(node, ["notes", "remark", "credit"]) ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")

        return ParsedClassDraft(
            title: title,
            teacher: stringValue(node, ["teacher", "teacherName", "jsxm"]) ?? "",
            location: location,
            weekday: weekday,
            startMinutes: start,
            endMinutes: end,
            weeks: weeks,
            notes: notes,
            timePending: false
        )
    }

    private static func stringValue(_ node: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = node[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
                return value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private static func intValue(_ node: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let value = node[key] as? Int { return value }
            if let value = node[key] as? String, let n = Int(value) { return n }
            if let value = node[key] as? NSNumber { return value.intValue }
        }
        return nil
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
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let key: String
            if draft.timePending {
                key = "pending|\(title)"
            } else {
                let weeks = (draft.weeks ?? []).map(String.init).joined(separator: ",")
                let room = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
                key = "\(title)|\(draft.weekday.rawValue)|\(draft.startMinutes)|\(draft.endMinutes)|\(room)|\(weeks)"
            }
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
        } else if let array = anyItems(any) {
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

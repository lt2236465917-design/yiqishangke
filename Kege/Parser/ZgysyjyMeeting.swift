import Foundation

/// Meeting strings from 研究生综合管理「我的课表」column「上课时间、地点」.
///
/// Verified shapes (user, desktop Safari):
/// - `5周1-上午课-虚拟教室1(主校区)`
/// - `6-11周一-下午课-6406(主校区)`
/// - `3,4周一-下午课-6406(主校区)`
/// Invalid / skip: `2label.teachtask.courseclass.week.null-排课室`
///
/// Mapping (节次时钟已由用户周课表截图核实；名单表无时钟时用时段默认):
/// - `周1` / `周一` = Monday … `周7` / `周日` = Sunday
/// - `上午课` = 09:00–12:00
/// - `下午课` = 13:30–16:30
/// - `晚上课` = 19:00–21:30
/// - 第一节…第十节见 `periodClock`
/// Row clocks like `09:00--12:00` override these defaults.
enum ZgysyjyMeeting {
    static let morning = (9 * 60, 12 * 60)
    static let afternoon = (13 * 60 + 30, 16 * 60 + 30)
    static let evening = (19 * 60, 21 * 60 + 30)

    /// Verified from weekly-grid screenshots (上午/下午/晚上切片).
    static let periodClock: [Int: (Int, Int)] = [
        1: (9 * 60, 9 * 60 + 45),
        2: (9 * 60 + 45, 10 * 60 + 30),
        3: (10 * 60 + 30, 11 * 60 + 15),
        4: (11 * 60 + 15, 12 * 60),
        5: (13 * 60 + 30, 14 * 60 + 15),
        6: (14 * 60 + 15, 15 * 60),
        7: (15 * 60, 15 * 60 + 45),
        8: (15 * 60 + 45, 16 * 60 + 30),
        9: (19 * 60, 19 * 60 + 40),
        10: (20 * 60 + 30, 21 * 60 + 30)
    ]

    enum PeriodKind: Equatable {
        case bandMorning
        case bandAfternoon
        case bandEvening
        case numbered(Int)

        var isBand: Bool {
            switch self {
            case .numbered: false
            default: true
            }
        }

        var minutes: (Int, Int) {
            switch self {
            case .bandMorning: ZgysyjyMeeting.morning
            case .bandAfternoon: ZgysyjyMeeting.afternoon
            case .bandEvening: ZgysyjyMeeting.evening
            case .numbered(let n): ZgysyjyMeeting.periodClock[n] ?? ZgysyjyMeeting.morning
            }
        }
    }

    static func periodKind(from text: String) -> PeriodKind? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if let n = numberedPeriod(compact) { return .numbered(n) }
        if compact.contains("上午") { return .bandMorning }
        if compact.contains("下午") { return .bandAfternoon }
        if compact.contains("晚上") || compact.contains("晚课") { return .bandEvening }
        return nil
    }

    static func numberedPeriod(_ text: String) -> Int? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let pattern = #"第\s*([0-9一二三四五六七八九十]+)\s*节"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: compact, range: NSRange(compact.startIndex..., in: compact)),
              let range = Range(match.range(at: 1), in: compact) else {
            return nil
        }
        let raw = String(compact[range])
        if let n = Int(raw), (1...12).contains(n) { return n }
        let map = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
        return map[raw]
    }

    /// Broken graduate-system placeholder, e.g. `2label.teachtask.courseclass.week.null-自排教室…`
    static func isBrokenPlaceholder(_ text: String) -> Bool {
        let compact = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .lowercased()
        guard !compact.isEmpty else { return false }
        if compact.contains("label.teachtask") { return true }
        if compact.contains("courseclass.week.null") { return true }
        if compact.contains("teachtask") && compact.contains("week.null") { return true }
        return false
    }

    static func isPendingMeeting(_ text: String, title: String = "") -> Bool {
        if isBrokenPlaceholder(text) { return true }
        let compact = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\n", with: "")
        let titleCompact = title.replacingOccurrences(of: " ", with: "")
        let keys = ["待定", "联系老师", "自行安排", "自排课", "时间地点待定", "时间、地点待定"]
        if keys.contains(where: { compact.contains($0) || titleCompact.contains($0) }) {
            return true
        }
        if titleCompact.contains("导师课") && (compact.isEmpty || parseCell(text).isEmpty) {
            return true
        }
        return compact.isEmpty
    }

    static func periodMinutes(from token: String) -> (Int, Int)? {
        if token.contains("上午") { return morning }
        if token.contains("下午") { return afternoon }
        if token.contains("晚上") || token.contains("晚课") { return evening }
        return nil
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

    static func parseWeeksPrefix(_ text: String) -> [Int]? {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return nil }
        var weeks: [Int] = []
        for part in compact.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "、" }) {
            let piece = String(part)
            if let dash = piece.rangeOfCharacter(from: CharacterSet(charactersIn: "-–—")),
               let a = Int(piece[piece.startIndex..<dash.lowerBound]),
               let b = Int(piece[dash.upperBound...]),
               a <= b, (1...30).contains(a), (1...30).contains(b) {
                weeks.append(contentsOf: a...b)
                continue
            }
            if let n = Int(piece), (1...30).contains(n) {
                weeks.append(n)
            }
        }
        return weeks.isEmpty ? nil : Array(Set(weeks)).sorted()
    }

    /// One line → one meeting. Returns nil to skip.
    static func parseLine(_ raw: String) -> (weekday: ChinaWeekday, start: Int, end: Int, weeks: [Int]?, room: String)? {
        let line = raw
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        if isBrokenPlaceholder(line) { return nil }

        let pattern = #"^(\d{1,2}(?:[-–—]\d{1,2})?(?:[,，、]\d{1,2}(?:[-–—]\d{1,2})?)*)(周[1-7一二三四五六日天])-(上午课|下午课|晚上课)-(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let weeksRange = Range(match.range(at: 1), in: line),
              let dayRange = Range(match.range(at: 2), in: line),
              let periodRange = Range(match.range(at: 3), in: line),
              let roomRange = Range(match.range(at: 4), in: line),
              let weekday = ChinaWeekday.parse(from: String(line[dayRange])),
              let minutes = periodMinutes(from: String(line[periodRange])) else {
            return nil
        }
        let weeks = parseWeeksPrefix(String(line[weeksRange]))
        let room = String(line[roomRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (weekday, minutes.0, minutes.1, weeks, room)
    }

    static func parseCell(_ cell: String) -> [(weekday: ChinaWeekday, start: Int, end: Int, weeks: [Int]?, room: String)] {
        let normalized = cell
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(parseLine)
    }

    /// Weekly-grid cell: one or more courses (name / teacher / weeks / room).
    static func parseGridCell(
        _ raw: String,
        weekday: ChinaWeekday,
        start: Int,
        end: Int
    ) -> ParsedClassDraft? {
        parseGridCells(raw, weekday: weekday, start: start, end: end).first
    }

    static func parseGridCells(
        _ raw: String,
        weekday: ChinaWeekday,
        start: Int,
        end: Int
    ) -> [ParsedClassDraft] {
        let lines = raw
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !isBrokenPlaceholder($0) }
            .filter { periodKind(from: $0) == nil }
            .filter { ChinaWeekday.parseColumnHeader($0) == nil }
            .filter { parseClockRange($0) == nil }
        guard !lines.isEmpty else { return [] }

        var blocks: [[String]] = []
        var current: [String] = []
        for line in lines {
            let startsNew = looksLikeTitle(line)
                && current.contains(where: looksLikeTitle)
                && current.contains(where: { looksLikeRoom($0) || looksLikePersonName($0) || TimetableHeuristics.parseWeeks($0) != nil || weeksFromLooseLine($0) != nil })
            if startsNew {
                blocks.append(current)
                current = [line]
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }
        return blocks.compactMap { parseBlock($0, weekday: weekday, start: start, end: end) }
    }

    private static func parseBlock(
        _ lines: [String],
        weekday: ChinaWeekday,
        start: Int,
        end: Int
    ) -> ParsedClassDraft? {
        var title = ""
        var teacher = ""
        var location = ""
        var weeks: [Int]?
        var leftovers: [String] = []

        for line in lines {
            if let parsedWeeks = TimetableHeuristics.parseWeeks(line) ?? weeksFromLooseLine(line) {
                weeks = parsedWeeks
                continue
            }
            if let named = teacherName(in: line) {
                teacher = named
                continue
            }
            if looksLikeRoom(line) && location.isEmpty {
                location = line
                continue
            }
            if title.isEmpty && looksLikeTitle(line) {
                title = line
                continue
            }
            leftovers.append(line)
        }

        if title.isEmpty {
            title = leftovers.first(where: looksLikeTitle) ?? leftovers.first ?? ""
            leftovers.removeAll { $0 == title }
        }
        if teacher.isEmpty, let maybe = leftovers.first(where: looksLikePersonName) {
            teacher = maybe
            leftovers.removeAll { $0 == maybe }
        }
        if location.isEmpty {
            location = leftovers.first(where: looksLikeRoom) ?? leftovers.last(where: { !$0.isEmpty }) ?? ""
        }
        guard title.count >= 2 else { return nil }
        if title.contains("虚拟教室") && teacher.isEmpty { return nil }

        return ParsedClassDraft(
            title: title,
            teacher: teacher,
            location: location,
            weekday: weekday,
            startMinutes: start,
            endMinutes: end,
            weeks: weeks,
            notes: ""
        )
    }

    private static func weeksFromLooseLine(_ line: String) -> [Int]? {
        let compact = line.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "周", with: "")
        guard compact.range(of: #"^\d{1,2}(?:[-–—,，、]\d{1,2})+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return parseWeeksPrefix(compact)
    }

    private static func teacherName(in line: String) -> String? {
        let pattern = #"(?:教师|老师|授课)[:：]?\s*([\u{4e00}-\u{9fff}A-Za-z]{2,12})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return String(line[range])
    }

    private static func looksLikeTitle(_ line: String) -> Bool {
        guard line.count >= 2, line.count <= 40 else { return false }
        if looksLikeRoom(line) { return false }
        if periodKind(from: line) != nil { return false }
        if TimetableHeuristics.parseWeeks(line) != nil || weeksFromLooseLine(line) != nil { return false }
        if looksLikePersonName(line) && line.count <= 4 { return false }
        if line.contains("节次") || line.contains("星期") { return false }
        return line.rangeOfCharacter(from: cjkAndLetters) != nil
    }

    private static func looksLikePersonName(_ line: String) -> Bool {
        let t = line.replacingOccurrences(of: " ", with: "")
        guard (2...4).contains(t.count) else { return false }
        return t.unicodeScalars.allSatisfy { cjkAndLetters.contains($0) }
    }

    private static func looksLikeRoom(_ line: String) -> Bool {
        if line.contains("校区") || line.contains("教室") || line.contains("排课室") { return true }
        if line.range(of: #"^\d{3,5}(?:\(.*\))?$"#, options: .regularExpression) != nil { return true }
        return line.contains("虚拟教室")
    }

    private static let cjkAndLetters: CharacterSet = {
        let cjk = CharacterSet(charactersIn: Unicode.Scalar(0x4E00)!...Unicode.Scalar(0x9FFF)!)
        return cjk.union(.letters)
    }()
}

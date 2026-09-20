import Foundation

/// Meeting strings from 研究生综合管理「我的课表」column「上课时间、地点」.
///
/// Verified shapes (user, desktop Safari):
/// - `5周1-上午课-虚拟教室1(主校区)`
/// - `6-11周一-下午课-6406(主校区)`
/// - `3,4周一-下午课-6406(主校区)`
/// Invalid / skip: `2label.teachtask.courseclass.week.null-排课室`
///
/// Mapping assumptions (school did not publish 节次对照):
/// - `周1` / `周一` = Monday … `周7` / `周日` = Sunday
/// - `上午课` = 08:00–11:40 when the weekly grid has no clock
/// - `下午课` = 14:00–17:40
/// - `晚上课` = 19:00–21:00 (not seen yet; reserved)
/// Weekly grid row clocks like `09:00--12:00` override those defaults.
enum ZgysyjyMeeting {
    static let morning = (8 * 60, 11 * 60 + 40)
    static let afternoon = (14 * 60, 17 * 60 + 40)
    static let evening = (19 * 60, 21 * 60)

    static func isBrokenPlaceholder(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("label.teachtask") || t.contains("week.null") || t.contains(".null-")
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

    /// Weekly-grid cell: course name / teacher / weeks / room (order inferred).
    static func parseGridCell(
        _ raw: String,
        weekday: ChinaWeekday,
        start: Int,
        end: Int
    ) -> ParsedClassDraft? {
        let lines = raw
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .filter { !isBrokenPlaceholder($0) }
        guard !lines.isEmpty else { return nil }

        var title = ""
        var teacher = ""
        var location = ""
        var weeks: [Int]?
        var leftovers: [String] = []

        for line in lines {
            if periodMinutes(from: line) != nil && line.count <= 4 { continue }
            if ChinaWeekday.parseColumnHeader(line) != nil { continue }
            if parseClockRange(line) != nil { continue }
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
            if let idx = leftovers.firstIndex(of: title) {
                leftovers.remove(at: idx)
            }
        }
        if teacher.isEmpty, let maybe = leftovers.first(where: looksLikePersonName) {
            teacher = maybe
            leftovers.removeAll { $0 == maybe }
        }
        if location.isEmpty {
            location = leftovers.first(where: looksLikeRoom) ?? leftovers.last ?? ""
        }
        guard title.count >= 2 else { return nil }

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
        if looksLikePersonName(line) && line.count <= 4 { return false }
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

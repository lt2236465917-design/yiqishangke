import Foundation
import CoreGraphics

struct OCRToken: Sendable, Equatable {
    var text: String
    /// Normalized box, origin top-left, unit square.
    var box: CGRect
    var confidence: Float

    var midX: CGFloat { box.midX }
    var midY: CGFloat { box.midY }
}

/// Rebuild the graduate weekly grid from Vision boxes (not line-joined OCR).
enum WeeklyGridOCRParser {
    static func drafts(from tokens: [OCRToken]) -> [ParsedClassDraft] {
        let useful = tokens
            .map { OCRToken(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box, confidence: $0.confidence) }
            .filter { !$0.text.isEmpty }
        guard useful.count >= 6 else { return [] }

        let columns = detectDayColumns(in: useful)
        guard !columns.isEmpty else { return [] }
        let periodMaxX = columns.map(\.minX).min() ?? 0.18
        let left = useful.filter { $0.midX < periodMaxX }
        let rows = detectPeriodRows(leftColumn: left, fallback: useful)
        guard !rows.isEmpty else { return [] }

        let numbered = rows.filter { !$0.kind.isBand }
        let chosen = numbered.isEmpty ? rows : numbered

        var drafts: [ParsedClassDraft] = []
        for row in chosen {
            for column in columns {
                let cellTokens = useful.filter { token in
                    column.range.contains(token.midX)
                        && row.range.contains(token.midY)
                        && token.midX >= periodMaxX
                }
                .sorted { lhs, rhs in
                    if abs(lhs.midY - rhs.midY) > 0.012 { return lhs.midY < rhs.midY }
                    return lhs.midX < rhs.midX
                }
                let text = cellTokens.map(\.text).joined(separator: "\n")
                drafts.append(contentsOf: ZgysyjyMeeting.parseGridCells(
                    text,
                    weekday: column.weekday,
                    start: row.start,
                    end: row.end
                ))
            }
        }
        return mergeAndDedupe(drafts)
    }

    static func mergeAndDedupe(_ drafts: [ParsedClassDraft]) -> [ParsedClassDraft] {
        let unique = uniqueMeetings(drafts)
        return uniqueMeetings(mergeConsecutive(unique))
    }

    static func uniqueMeetings(_ drafts: [ParsedClassDraft]) -> [ParsedClassDraft] {
        var seen = Set<String>()
        return drafts.filter { draft in
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let weeks = (draft.weeks ?? []).map(String.init).joined(separator: ",")
            let room = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(title)|\(draft.weekday.rawValue)|\(draft.startMinutes)|\(draft.endMinutes)|\(room)|\(weeks)"
            return seen.insert(key).inserted
        }
    }

    static func mergeConsecutive(_ drafts: [ParsedClassDraft]) -> [ParsedClassDraft] {
        let sorted = drafts.sorted {
            if $0.weekday != $1.weekday { return $0.weekday.rawValue < $1.weekday.rawValue }
            if $0.title != $1.title { return $0.title < $1.title }
            let lw = ($0.weeks ?? []).map(String.init).joined()
            let rw = ($1.weeks ?? []).map(String.init).joined()
            if lw != rw { return lw < rw }
            return $0.startMinutes < $1.startMinutes
        }
        var result: [ParsedClassDraft] = []
        for draft in sorted {
            if var last = result.last,
               last.title == draft.title,
               last.weekday == draft.weekday,
               last.weeks == draft.weeks,
               (last.teacher.isEmpty || draft.teacher.isEmpty || last.teacher == draft.teacher),
               (last.location.isEmpty || draft.location.isEmpty || last.location == draft.location),
               draft.startMinutes <= last.endMinutes + 20 {
                last.endMinutes = max(last.endMinutes, draft.endMinutes)
                if last.teacher.isEmpty { last.teacher = draft.teacher }
                if last.location.isEmpty { last.location = draft.location }
                result[result.count - 1] = last
            } else {
                result.append(draft)
            }
        }
        return result
    }

    private struct DayColumn {
        var weekday: ChinaWeekday
        var minX: CGFloat
        var maxX: CGFloat
        var range: ClosedRange<CGFloat> { minX...maxX }
    }

    private struct PeriodRow {
        var kind: ZgysyjyMeeting.PeriodKind
        var start: Int
        var end: Int
        var range: ClosedRange<CGFloat>
    }

    private static func detectDayColumns(in tokens: [OCRToken]) -> [DayColumn] {
        var headers: [(ChinaWeekday, CGFloat)] = []
        for token in tokens {
            let compact = token.text.replacingOccurrences(of: " ", with: "")
            guard compact.count <= 8, let day = ChinaWeekday.parseColumnHeader(compact) else { continue }
            headers.append((day, token.midX))
        }
        if Set(headers.map(\.0)).count >= 3 {
            let grouped = Dictionary(grouping: headers, by: \.0)
                .compactMap { weekday, items -> (ChinaWeekday, CGFloat)? in
                    let xs = items.map(\.1)
                    return (weekday, xs.reduce(0, +) / CGFloat(xs.count))
                }
                .sorted { $0.1 < $1.1 }
            return columns(fromCenters: grouped)
        }

        let centers = clusterAxis(tokens.map(\.midX), gap: 0.05)
        guard centers.count >= 6 else { return [] }
        let dayCenters = centers.count >= 8 ? Array(centers.dropFirst()) : centers
        let days = Array(ChinaWeekday.allCases.prefix(dayCenters.count))
        return columns(fromCenters: Array(zip(days, dayCenters)))
    }

    private static func columns(fromCenters pairs: [(ChinaWeekday, CGFloat)]) -> [DayColumn] {
        guard !pairs.isEmpty else { return [] }
        var result: [DayColumn] = []
        for (index, pair) in pairs.enumerated() {
            let prev = index == 0 ? pair.1 - 0.08 : (pairs[index - 1].1 + pair.1) / 2
            let next = index == pairs.count - 1 ? pair.1 + 0.08 : (pair.1 + pairs[index + 1].1) / 2
            result.append(DayColumn(weekday: pair.0, minX: prev, maxX: next))
        }
        return result
    }

    private static func detectPeriodRows(leftColumn: [OCRToken], fallback: [OCRToken]) -> [PeriodRow] {
        let source = leftColumn.isEmpty ? fallback : leftColumn
        let groups = clusterTokens(source, alongY: true, gap: 0.032)
        var raw: [(kind: ZgysyjyMeeting.PeriodKind, start: Int, end: Int, y: CGFloat)] = []
        for group in groups {
            let blob = group.map(\.text).joined(separator: "\n")
            guard let kind = ZgysyjyMeeting.periodKind(from: blob) else { continue }
            let clock = ZgysyjyMeeting.parseClockRange(blob) ?? kind.minutes
            let y = group.map(\.midY).reduce(0, +) / CGFloat(group.count)
            raw.append((kind, clock.0, clock.1, y))
        }
        raw.sort { $0.y < $1.y }
        guard !raw.isEmpty else { return [] }

        var rows: [PeriodRow] = []
        for (index, item) in raw.enumerated() {
            let top = index == 0 ? max(0, item.y - 0.06) : (raw[index - 1].y + item.y) / 2
            let bottom = index == raw.count - 1 ? min(1, item.y + 0.08) : (item.y + raw[index + 1].y) / 2
            rows.append(PeriodRow(kind: item.kind, start: item.start, end: item.end, range: top...bottom))
        }
        return rows
    }

    private static func clusterTokens(_ tokens: [OCRToken], alongY: Bool, gap: CGFloat) -> [[OCRToken]] {
        let sorted = tokens.sorted { alongY ? $0.midY < $1.midY : $0.midX < $1.midX }
        var groups: [[OCRToken]] = []
        for token in sorted {
            let value = alongY ? token.midY : token.midX
            if var last = groups.last {
                let lastValue = last.map { alongY ? $0.midY : $0.midX }.reduce(0, +) / CGFloat(last.count)
                if abs(value - lastValue) < gap {
                    last.append(token)
                    groups[groups.count - 1] = last
                    continue
                }
            }
            groups.append([token])
        }
        return groups
    }

    private static func clusterAxis(_ values: [CGFloat], gap: CGFloat) -> [CGFloat] {
        let sorted = values.sorted()
        var groups: [[CGFloat]] = []
        for value in sorted {
            if var last = groups.last, let mean = last.first, abs(value - (last.reduce(0, +) / CGFloat(last.count))) < gap || abs(value - mean) < gap {
                last.append(value)
                groups[groups.count - 1] = last
            } else {
                groups.append([value])
            }
        }
        return groups.map { $0.reduce(0, +) / CGFloat($0.count) }
    }
}

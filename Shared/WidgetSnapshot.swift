import Foundation

/// Compact payload written by the app and read by home screen widgets.
struct WidgetSnapshot: Codable, Sendable {
    var generatedAt: Date
    var nextClass: WidgetClassCard?
    var remainingToday: [WidgetClassCard]

    struct WidgetClassCard: Codable, Sendable, Identifiable {
        var id: UUID
        var title: String
        var teacher: String
        var location: String
        var weekdayLabel: String
        var timeRangeLabel: String
        var startMinutes: Int
        var endMinutes: Int

        var startClock: String { ClassSession.clockLabel(startMinutes) }
        var endClock: String { ClassSession.clockLabel(endMinutes) }
        var clockRange: String { "\(startClock)–\(endClock)" }

        /// Medium widget row: `09:00 · 6607 · 课名`
        var remainingLine: String {
            var parts = [startClock]
            let room = location.trimmingCharacters(in: .whitespacesAndNewlines)
            if !room.isEmpty { parts.append(room) }
            let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { parts.append(name) }
            return parts.joined(separator: " · ")
        }
    }

    static let empty = WidgetSnapshot(generatedAt: Date.distantPast, nextClass: nil, remainingToday: [])

    static func load(from url: URL = AppGroup.widgetSnapshotURL) -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: url) else { return .empty }
        return (try? JSONDecoder.kege.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}

extension JSONEncoder {
    static var kege: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var kege: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

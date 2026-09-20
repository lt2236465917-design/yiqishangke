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

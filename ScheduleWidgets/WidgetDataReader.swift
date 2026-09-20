import Foundation

enum WidgetDataReader {
    static func snapshot() -> WidgetSnapshot {
        WidgetSnapshot.load()
    }
}

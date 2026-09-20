import Foundation
import SwiftUI

enum WidgetDataReader {
    static func snapshot() -> WidgetSnapshot {
        WidgetSnapshot.load()
    }
}

enum WidgetLook {
    static let paper = Color(red: 0.965, green: 0.945, blue: 0.910)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let muted = Color(red: 0.11, green: 0.10, blue: 0.09).opacity(0.52)
}

import Foundation
import os.log

/// Logging that must never receive passwords, tokens, or school-credential payloads.
enum SafeLog {
    private static let logger = Logger(subsystem: "cn.yiqishangke.Kege", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

enum Redaction {
    static func username(_ value: String) -> String {
        guard !value.isEmpty else { return "<empty>" }
        if value.count <= 2 { return "**" }
        return String(value.prefix(1)) + String(repeating: "*", count: min(value.count - 1, 6))
    }
}

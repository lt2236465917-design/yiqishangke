import Foundation

enum FixtureFile {
    static func url(_ name: String) throws -> URL {
        let bundle = Bundle.module
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        if let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures") {
            return url
        }
        if let url = bundle.url(forResource: stem, withExtension: ext, subdirectory: "Fixtures") {
            return url
        }
        if let url = bundle.url(forResource: stem, withExtension: ext) {
            return url
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            cwd.appendingPathComponent("ParserRegression/Fixtures/\(name)"),
            cwd.appendingPathComponent("Fixtures/\(name)")
        ]
        if let hit = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return hit
        }
        throw FixtureError.missing(name)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: try url(name))
    }

    static func string(_ name: String) throws -> String {
        String(decoding: try data(name), as: UTF8.self)
    }

    enum FixtureError: Error {
        case missing(String)
    }
}

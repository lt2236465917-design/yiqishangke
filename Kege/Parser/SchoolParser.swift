import Foundation

enum SchoolParser {
    static let zgysyjy = ZgysyjyParser()

    static var loginURL: URL { ZgysyjyParser.loginURL }

    static func parse(html: String, pageURL: URL?, innerText: String?) -> ParseResult {
        zgysyjy.parse(html: html, pageURL: pageURL, innerText: innerText)
    }
}

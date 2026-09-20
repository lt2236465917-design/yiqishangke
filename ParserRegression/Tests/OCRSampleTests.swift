import Foundation
import XCTest
@testable import KegeParser

final class OCRSampleTests: XCTestCase {
    func testModelJSONSampleWithoutLiveAPI() throws {
        let json = try FixtureFile.string("ocr-model-sample.json")
        var drafts = TimetableHeuristics.drafts(fromStructuredJSON: json)
        drafts = WeeklyGridOCRParser.mergeAndDedupe(drafts)
        GoldenAssert.sessions(drafts, label: "ocr-model-sample")
    }

    func testMergeAndDedupeConsecutivePeriodsDistinctWeeksAndTBD() throws {
        let json = try FixtureFile.string("ocr-merge-input.json")
        var drafts = TimetableHeuristics.drafts(fromStructuredJSON: json)
        drafts = WeeklyGridOCRParser.mergeAndDedupe(drafts)

        let scheduled = drafts.filter { !$0.timePending }
        let pending = drafts.filter(\.timePending)
        XCTAssertEqual(scheduled.count, 3)
        XCTAssertEqual(Set(pending.map(\.title)), ["导师课", "思政大讲堂：形势与政策"])

        let heritage = try XCTUnwrap(scheduled.first { $0.title == "遗产概论" })
        XCTAssertEqual(heritage.startMinutes, 9 * 60)
        XCTAssertEqual(heritage.endMinutes, 10 * 60 + 30)

        let art = scheduled.filter { $0.title == "东亚艺术通史" }
        XCTAssertEqual(art.count, 2, "distinct week ranges must not collapse")
        XCTAssertEqual(Set(art.map(\.startMinutes)), [13 * 60 + 30])
        XCTAssertNotEqual(art[0].weeks, art[1].weeks)
    }

    func testMergeAndDedupeKeepsPendingUniqueByTitle() {
        let drafts = [
            TimetableHeuristics.pendingDraft(title: "导师课", teacher: "", notes: "时间、地点待定"),
            TimetableHeuristics.pendingDraft(title: "导师课", teacher: "", notes: "空格"),
            TimetableHeuristics.pendingDraft(title: "思政大讲堂：形势与政策", teacher: "", notes: "label.teachtask")
        ]
        let merged = WeeklyGridOCRParser.mergeAndDedupe(drafts)
        XCTAssertEqual(merged.filter(\.timePending).count, 2)
    }
}

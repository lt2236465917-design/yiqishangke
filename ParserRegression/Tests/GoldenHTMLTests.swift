import Foundation
import XCTest
@testable import KegeParser

final class GoldenHTMLTests: XCTestCase {
    func testHTMLGoldenYieldsTwentyThreeDistinctSessionsAndTBD() throws {
        let html = try FixtureFile.string("golden-my-schedule.html")
        XCTAssertTrue(html.contains("周一"))
        XCTAssertTrue(html.contains("上午课"))
        XCTAssertTrue(html.contains("第一节"))
        XCTAssertTrue(html.contains("上课周次、时间、地点"))
        XCTAssertTrue(html.contains("课程编码"))

        let result = ZgysyjyParser().parse(
            html: html,
            pageURL: URL(string: "https://wxt.zgysyjy.org.cn:7792/graduate/student/kb.jsp"),
            innerText: nil
        )
        XCTAssertNil(result.blocker)
        GoldenAssert.sessions(result.classes, label: "html")
    }

    func testExtractScheduleTablesJSONMatchesHTMLGolden() throws {
        let data = try FixtureFile.data("extract-schedule-tables.json")
        let object = try JSONSerialization.jsonObject(with: data)
        let slices = HTMLTableSlice.slices(fromJavaScriptTables: object)
        XCTAssertGreaterThanOrEqual(slices.count, 2)

        let result = ZgysyjyParser().parse(
            html: "",
            pageURL: URL(string: "https://wxt.zgysyjy.org.cn:7792/graduate/student/kb.jsp"),
            innerText: nil,
            slices: slices
        )
        GoldenAssert.sessions(result.classes, label: "extract-schedule-tables")
    }

    func testListHeaderAcceptsCourseCodeAndWeekColumn() {
        let header = ["课程编码", "课程名称", "班次", "学分", "上课周次、时间、地点", "选课性质", "是否选中"]
        let html = """
        <table>
        <tr>\(header.map { "<th>\($0)</th>" }.joined())</tr>
        <tr><td>SYN1</td><td>东亚艺术通史</td><td>1</td><td>2.0</td>
        <td>6-11周一-下午课-6406(主校区)<br>3,4周一-下午课-6406(主校区)</td>
        <td>正常考试</td><td>选中</td></tr>
        </table>
        """
        let result = ZgysyjyParser().parse(html: html, pageURL: nil, innerText: nil)
        let scheduled = result.classes.filter { !$0.timePending }
        XCTAssertEqual(scheduled.count, 2)
        XCTAssertEqual(Set(scheduled.map(\.startMinutes)), [13 * 60 + 30])
        XCTAssertNotEqual(scheduled[0].weeks, scheduled[1].weeks)
    }
}

enum GoldenAssert {
    static func sessions(_ drafts: [ParsedClassDraft], label: String, scheduledCount: Int = 23, pendingCount: Int = 2) {
        let scheduled = drafts.filter { !$0.timePending }
        let pending = drafts.filter(\.timePending)
        XCTAssertEqual(scheduled.count, scheduledCount, "\(label) scheduled")
        XCTAssertEqual(pending.count, pendingCount, "\(label) pending")

        let pendingTitles = Set(pending.map(\.title))
        XCTAssertTrue(pendingTitles.contains("导师课"), "\(label) missing 导师课 TBD")
        XCTAssertTrue(pendingTitles.contains(where: { $0.contains("思政") }), "\(label) missing 思政 TBD")

        let starts = Set(scheduled.map(\.startMinutes))
        XCTAssertFalse(
            scheduled.allSatisfy { $0.startMinutes == 9 * 60 && $0.endMinutes == 12 * 60 },
            "\(label) collapsed every session to 09:00–12:00"
        )
        XCTAssertTrue(starts.contains(9 * 60), "\(label) missing morning")
        XCTAssertTrue(starts.contains(13 * 60 + 30), "\(label) missing afternoon")
        XCTAssertTrue(starts.contains(19 * 60), "\(label) missing evening")

        let identities = Set(scheduled.map {
            "\($0.title)|\($0.weekday.rawValue)|\($0.startMinutes)|\(($0.weeks ?? []).map(String.init).joined(separator: ","))"
        })
        XCTAssertEqual(identities.count, scheduled.count, "\(label) duplicate scheduled identities")
    }
}

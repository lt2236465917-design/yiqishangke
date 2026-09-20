import Foundation
import UIKit

/// Optional multimodal vision via developer-injected API key. Never sends school credentials.
struct MultimodalAIEngine: Sendable {
    var configuration: AIVisionConfiguration

    func recognizeTimetable(image: UIImage) async throws -> String {
        try await recognizeTimetable(images: [image])
    }

    func recognizeTimetable(images: [UIImage]) async throws -> String {
        guard configuration.isUsable else { throw ScreenshotImporterError.missingAPIKey }
        let jpegs = images.compactMap { $0.jpegData(compressionQuality: 0.72) }
        guard !jpegs.isEmpty else { throw ScreenshotImporterError.invalidImage }

        guard let url = configuration.chatCompletionsURL else { throw ScreenshotImporterError.aiRejected }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        var content: [[String: Any]] = [
            ["type": "text", "text": Self.userPrompt]
        ]
        for jpeg in jpegs {
            content.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())",
                    "detail": "high"
                ]
            ])
        }

        let body: [String: Any] = [
            "model": configuration.resolvedModel,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": content]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        SafeLog.info("Sending \(jpegs.count) timetable image(s) to developer vision endpoint (no credentials in payload)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenshotImporterError.aiRejected
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let contentText = message["content"] as? String else {
            throw ScreenshotImporterError.aiRejected
        }
        return normalizeJSON(contentText)
    }

    static let systemPrompt = """
    你是中国艺术研究院研究生「我的课表」结构化助手。图可能是学期课表名单、周课表网格，或两者都有。
    只返回 JSON，不要 markdown，不要解释。不要编造未出现的课，不要把下午课/晚上课写成 09:00-12:00。

    优先返回对象：
    {
      "scheduled": [
        {
          "title": "课名",
          "teacher": "教师，可空",
          "weekday": "周一",
          "periodLabel": "上午课 或 下午课 或 晚上课 或 第一节",
          "startTime": "13:30",
          "endTime": "16:30",
          "weeks": "6-13",
          "room": "6310",
          "sourceLine": "6-13周一-下午课-6310"
        }
      ],
      "pending": [
        { "title": "导师课", "teacher": "", "reason": "时间、地点待定" }
      ]
    }
    也兼容课程数组，或 { "courses": [ { "title", "timePending", "meetings": [...] } ] }。

    规则：
    1. 若有名单表「上课时间、地点」或「上课周次、时间、地点」，每一条有效行出一条 scheduled。格式如 `6周1-上午课-虚拟教室2(主校区)`、`6-13周一-下午课-6310`、`3,4周一-下午课-6406`。把原行放进 sourceLine。
    2. 周网格只补充名单没有的格。列=周一…周日。行时钟优先用该行左侧 HH:MM（09:00-12:00 / 13:30-16:30 / 19:00-21:30），不要一律写成上午。
    3. 同一门课不同周次行保持多条（例如硕士英语三行三个 weeks）。同一门课相邻第N节、同一天同一周次可合成一条，start=第一节开始、end=最后一节结束。
    4. 坏行不要当课时：label.teachtask、week.null、排课室乱码、未选中。思政若只有「联系老师/自行安排/坏行」→ pending，不要假造星期时段。
    5. 导师课或上课时间为空 → pending，reason 用「时间、地点待定」。
    6. 时段映射：上午课 09:00-12:00；下午课 13:30-16:30；晚上课 19:00-21:30。第1-4节在上午，第5-8节在下午，第9-10节在晚上。
    7. 忽略导航、顶栏、表头、「上午课」单独当课名、虚拟教室占位当课名。不要索要账号密码。
    """

    static let userPrompt = """
    这些图是研究生「我的课表」截图（可能含学期课表名单 + 下方周网格，或上午/下午/晚上切片）。
    先读名单「上课时间、地点」每一行；周网格只补缺。空时间/导师课/思政自排标 pending。
    不要把所有课都写成 09:00-12:00。合并去重后只返回一个 JSON。
    """

    static let textUserPrompt = """
    下面是研究生「我的课表」网页或 OCR 纯文本。优先按名单行 `周次+周N+上午课/下午课/晚上课+教室` 提取。
    坏行和空导师课放入 pending。不要把下午课写成 09:00-12:00。只返回一个 JSON。
    """

    /// Text-only cleanup. Never sends images or school credentials.
    func recognizeTimetable(plainText: String) async throws -> String {
        guard configuration.isUsable else { throw ScreenshotImporterError.missingAPIKey }
        let clipped = String(plainText.prefix(14000))
        guard !clipped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotImporterError.emptyRecognition
        }
        guard let url = configuration.chatCompletionsURL else { throw ScreenshotImporterError.aiRejected }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90

        let body: [String: Any] = [
            "model": configuration.resolvedModel,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": Self.textUserPrompt + "\n\n" + clipped]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        SafeLog.info("Sending timetable plain text to developer endpoint (no images, no credentials)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenshotImporterError.aiRejected
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let contentText = message["content"] as? String else {
            throw ScreenshotImporterError.aiRejected
        }
        return normalizeJSON(contentText)
    }

    private func normalizeJSON(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```(?:json)?"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

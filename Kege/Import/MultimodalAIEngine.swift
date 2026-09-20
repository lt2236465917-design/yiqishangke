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
    你是课表结构化助手。根据研究生「我的课表」周课表截图或门户 WebView 快照提取课程。
    只返回 JSON 数组，不要 markdown，不要解释。
    数组元素字段：
    - title (string, 必填)
    - teacher (string, 可空)
    - weekday (1-7 或 周一…周日, 必填；1=周一)
    - periodLabel (string, 如 第一节/上午课, 可空)
    - startTime (HH:MM, 必填，优先用该行左侧时钟)
    - endTime (HH:MM, 必填)
    - weeks (string 如 "6-13" 或 "3,4"，或数字数组)
    - room (string, 可空)
    - campus (string, 可空)
    只提取真实课程：课名、星期、上下课时间、教室/地点（有则填）。同一格多门课拆成多项。
    必须忽略：左侧导航、顶栏、页眉、按钮、工作台、登录态、表头、「上午课/下午课/晚上课」单独当课程、空格、虚拟教室占位、乱码、以及损坏的 i18n 键（如 label.xxx、week.null、teachtask）。
    不要编造未出现的课。不要索要或回显任何账号、密码、Cookie、Token。
    """

    static let userPrompt = """
    这些图是同一周课表（网页快照或上午/下午/晚上切片）。可能含左侧「我的课表」菜单和系统铬。
    忽略导航和标签噪音，只从周课表格子提取真实课程。列=周一…周日，行=上午课/下午课/晚上课或第N节。
    合并去重后只返回一个 JSON。
    """

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

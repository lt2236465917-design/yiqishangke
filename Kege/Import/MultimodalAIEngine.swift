import Foundation
import UIKit

/// Optional multimodal vision via developer-injected API key. Never sends school credentials.
struct MultimodalAIEngine: Sendable {
    var configuration: AIVisionConfiguration

    func recognizeTimetable(image: UIImage) async throws -> String {
        guard configuration.isUsable else { throw ScreenshotImporterError.missingAPIKey }
        guard let jpeg = image.jpegData(compressionQuality: 0.7) else { throw ScreenshotImporterError.invalidImage }

        let root = configuration.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(root)/chat/completions") else { throw ScreenshotImporterError.aiRejected }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let prompt = """
        你是课表结构化助手。只根据这张课表截图提取课程。
        只返回 JSON 数组，不要 markdown，不要解释。
        每项字段：title, teacher, location, weekday (1=周一…7=周日), start (HH:MM), end (HH:MM), weeks (数字数组，未知则省略)。
        不要索要或回显任何账号、密码、Cookie、Token。
        """

        let body: [String: Any] = [
            "model": configuration.model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": prompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": "提取课表。不要包含任何登录凭证。"],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(jpeg.base64EncodedString())"
                            ]
                        ]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        SafeLog.info("Sending timetable image to developer vision endpoint (no credentials in payload)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ScreenshotImporterError.aiRejected
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ScreenshotImporterError.aiRejected
        }
        return normalizeJSON(content)
    }

    private func normalizeJSON(_ content: String) -> String {
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: #"^```(?:json)?"#, with: "", options: .regularExpression)
            text = text.replacingOccurrences(of: #"```$"#, with: "", options: .regularExpression)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let data = text.data(using: .utf8),
           let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.compactMap { row in
                let title = row["title"] as? String ?? ""
                let teacher = row["teacher"] as? String ?? ""
                let location = row["location"] as? String ?? ""
                let weekday = row["weekday"] ?? ""
                let start = row["start"] as? String ?? ""
                let end = row["end"] as? String ?? ""
                return "周\(weekday) \(start)-\(end) \(title) 教师:\(teacher) 地点:\(location)"
            }.joined(separator: "\n")
        }
        return text
    }
}

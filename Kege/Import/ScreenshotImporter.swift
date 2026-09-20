import Foundation
import UIKit
import Vision

struct ImportOutcome: Equatable {
    var result: ParseResult
    var engine: String
}

protocol ScreenshotRecognizing: Sendable {
    func recognize(image: UIImage) async throws -> String
}

struct VisionOCREngine: ScreenshotRecognizing {
    func recognize(image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { throw ScreenshotImporterError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            func finish(_ result: Result<String, Error>) {
                guard !finished else { return }
                finished = true
                continuation.resume(with: result)
            }
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    finish(.failure(error))
                    return
                }
                let observations = (req.results as? [VNRecognizedTextObservation]) ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                finish(.success(lines.joined(separator: "\n")))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
            } catch {
                finish(.failure(error))
            }
        }
    }
}

enum ScreenshotImporterError: LocalizedError {
    case invalidImage
    case emptyRecognition
    case aiRejected
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取这张截图"
        case .emptyRecognition: "没有识别出文字"
        case .aiRejected: "识图接口返回无法解析"
        case .missingAPIKey: "未配置开发者识图 Key，将使用本机 OCR"
        }
    }
}

actor ScreenshotImporter {
    private let vision: ScreenshotRecognizing
    private let credentialsStore: CredentialsStore

    init(
        vision: ScreenshotRecognizing = VisionOCREngine(),
        credentialsStore: CredentialsStore = .shared
    ) {
        self.vision = vision
        self.credentialsStore = credentialsStore
    }

    func importImage(_ image: UIImage) async throws -> ImportOutcome {
        let aiConfig = try credentialsStore.loadAIConfiguration()
        if let aiConfig, aiConfig.isUsable {
            do {
                let outcome = try await importWithAI(image, config: aiConfig)
                if !outcome.result.classes.isEmpty { return outcome }
                SafeLog.info("AI vision returned no classes; falling back to OCR")
            } catch {
                SafeLog.error("AI vision failed, falling back to OCR: \(error.localizedDescription)")
            }
        }
        return try await importWithOCR(image)
    }

    private func importWithOCR(_ image: UIImage) async throws -> ImportOutcome {
        let text = try await vision.recognize(image: image)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ScreenshotImporterError.emptyRecognition
        }
        let drafts = TimetableHeuristics.drafts(fromPlainText: text)
        let result = ParseResult(
            classes: drafts,
            sourceDescription: "vision-ocr",
            blocker: drafts.isEmpty ? "OCR 未拼出完整课程行，可改用更清晰的课表截图。" : nil,
            rawExcerpt: String(text.prefix(600))
        )
        return ImportOutcome(result: result, engine: "Vision OCR")
    }

    private func importWithAI(_ image: UIImage, config: AIVisionConfiguration) async throws -> ImportOutcome {
        let engine = MultimodalAIEngine(configuration: config)
        let text = try await engine.recognizeTimetable(image: image)
        var drafts = TimetableHeuristics.drafts(fromPlainText: text)
        if let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            drafts.append(contentsOf: TimetableHeuristics.drafts(fromJSONObject: object))
            drafts = TimetableHeuristics.unique(drafts)
        }
        let result = ParseResult(
            classes: drafts,
            sourceDescription: "multimodal-ai",
            blocker: drafts.isEmpty ? "识图模型未返回可解析课表 JSON。" : nil,
            rawExcerpt: String(text.prefix(600))
        )
        return ImportOutcome(result: result, engine: "Multimodal AI")
    }
}

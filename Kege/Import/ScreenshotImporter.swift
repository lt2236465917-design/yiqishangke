import Foundation
import UIKit
import Vision

struct ImportOutcome: Equatable {
    var result: ParseResult
    var engine: String
}

protocol ScreenshotRecognizing: Sendable {
    func recognizeTokens(image: UIImage) async throws -> [OCRToken]
}

struct VisionOCREngine: ScreenshotRecognizing {
    func recognizeTokens(image: UIImage) async throws -> [OCRToken] {
        guard let cg = image.cgImage else { throw ScreenshotImporterError.invalidImage }
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            func finish(_ result: Result<[OCRToken], Error>) {
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
                let tokens = observations.compactMap { obs -> OCRToken? in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let box = obs.boundingBox
                    let topLeft = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
                    return OCRToken(text: candidate.string, box: topLeft, confidence: candidate.confidence)
                }
                finish(.success(tokens))
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
    case retriesExhausted(attempted: Int, last: String)

    static let maxAttempts = 5

    var errorDescription: String? {
        switch self {
        case .invalidImage: "无法读取这些截图"
        case .emptyRecognition: "没有识别出可用的课表格子。请一次选中上午/下午/晚上整页截图。"
        case .aiRejected: "识图接口返回无法解析"
        case .missingAPIKey: "未配置开发者识图 Key，将使用本机 OCR"
        case .retriesExhausted(let attempted, let last):
            "录入课表未能识别（已尝试 \(attempted) 次，不会再试）。\(last)"
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
        try await importImages([image])
    }

    func importImages(_ images: [UIImage]) async throws -> ImportOutcome {
        guard !images.isEmpty else { throw ScreenshotImporterError.invalidImage }
        let aiConfig = try credentialsStore.loadAIConfiguration()
        if let aiConfig, aiConfig.isUsable {
            let pair = try await recognizeWithAI(images, config: aiConfig)
            let merged = WeeklyGridOCRParser.mergeAndDedupe(pair.0)
            guard !merged.isEmpty else { throw ScreenshotImporterError.emptyRecognition }
            return ImportOutcome(
                result: ParseResult(
                    classes: merged,
                    sourceDescription: "vision-llm \(aiConfig.resolvedModel) x\(images.count)",
                    blocker: nil,
                    rawExcerpt: String(pair.1.prefix(600))
                ),
                engine: "多模态 \(aiConfig.resolvedModel)"
            )
        }

        var all: [ParsedClassDraft] = []
        var excerpts: [String] = []
        for (index, image) in images.enumerated() {
            let ocr = try await recognizeWithOCR(image)
            all.append(contentsOf: ocr.0)
            excerpts.append("[\(index + 1)/\(images.count)] \(ocr.1)")
        }
        let merged = WeeklyGridOCRParser.mergeAndDedupe(all)
        guard !merged.isEmpty else { throw ScreenshotImporterError.emptyRecognition }
        return ImportOutcome(
            result: ParseResult(
                classes: merged,
                sourceDescription: "screenshot-ocr-grid x\(images.count)",
                blocker: nil,
                rawExcerpt: String(excerpts.joined(separator: "\n").prefix(600))
            ),
            engine: "Vision OCR（未配置 Key）"
        )
    }

    /// Finite retries for the same images. Never loops forever. Merges by title+weekday+time+room+weeks.
    func importImagesWithRetries(
        _ images: [UIImage],
        maxAttempts: Int = ScreenshotImporterError.maxAttempts
    ) async throws -> ImportOutcome {
        let capped = min(max(maxAttempts, 1), ScreenshotImporterError.maxAttempts)
        var collected: [ParsedClassDraft] = []
        var lastError: Error?
        var lastEngine = ""
        var lastSource = ""
        var lastExcerpt = ""
        for attempt in 1...capped {
            do {
                let outcome = try await importImages(images)
                collected.append(contentsOf: outcome.result.classes)
                lastEngine = outcome.engine
                lastSource = outcome.result.sourceDescription
                lastExcerpt = outcome.result.rawExcerpt ?? ""
                let merged = WeeklyGridOCRParser.mergeAndDedupe(collected)
                if !merged.isEmpty {
                    return ImportOutcome(
                        result: ParseResult(
                            classes: merged,
                            sourceDescription: "\(lastSource) attempt=\(attempt)/\(capped)",
                            blocker: nil,
                            rawExcerpt: lastExcerpt
                        ),
                        engine: lastEngine
                    )
                }
            } catch {
                lastError = error
            }
        }
        let merged = WeeklyGridOCRParser.mergeAndDedupe(collected)
        if !merged.isEmpty {
            return ImportOutcome(
                result: ParseResult(
                    classes: merged,
                    sourceDescription: "\(lastSource) merged-retries",
                    blocker: nil,
                    rawExcerpt: lastExcerpt
                ),
                engine: lastEngine
            )
        }
        let last = lastError?.localizedDescription ?? ScreenshotImporterError.emptyRecognition.localizedDescription
        throw ScreenshotImporterError.retriesExhausted(attempted: capped, last: last)
    }

    private func recognizeWithOCR(_ image: UIImage) async throws -> ([ParsedClassDraft], String) {
        let tokens = try await vision.recognizeTokens(image: image)
        let text = tokens.map(\.text).joined(separator: "\n")
        var drafts = WeeklyGridOCRParser.drafts(from: tokens)
        if drafts.isEmpty {
            drafts = TimetableHeuristics.drafts(fromPlainText: text)
        }
        return (drafts, String(text.prefix(180)))
    }

    private func recognizeWithAI(_ images: [UIImage], config: AIVisionConfiguration) async throws -> ([ParsedClassDraft], String) {
        let engine = MultimodalAIEngine(configuration: config)
        let text = try await engine.recognizeTimetable(images: images)
        var drafts = TimetableHeuristics.drafts(fromStructuredJSON: text)
        if drafts.filter({ !$0.timePending }).isEmpty {
            let fallback = TimetableHeuristics.drafts(fromPlainText: text)
            drafts.append(contentsOf: fallback)
        }
        drafts = WeeklyGridOCRParser.mergeAndDedupe(drafts)
        return (drafts, text)
    }
}

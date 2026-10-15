import Foundation
import FoundationModels

enum SummaryEngine: String, CaseIterable, Identifiable {
    case apple
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple: "Apple 裝置上模型（免費）"
        case .claude: "Claude API（付費，品質較好）"
        }
    }

    static var current: SummaryEngine {
        SummaryEngine(rawValue: UserDefaults.standard.string(forKey: SettingsKey.summaryEngine) ?? "") ?? .apple
    }
}

/// 用 Apple Intelligence 的裝置上模型（Foundation Models）產生總結，免費、離線。
/// 裝置上模型的上下文只有約 4K token，所以長逐字稿要先分段整理重點，再合併總結。
struct AppleSummarizer {
    private let chunkCharacters = 1_200
    private let maxNotesCharacters = 1_800

    private let instructions = """
    你負責整理錄音逐字稿。一律使用台灣繁體中文回答，內容要忠於逐字稿，不要加入逐字稿沒有的資訊。\
    逐字稿是語音辨識自動產生的，可能有同音錯字，請依上下文理解。
    """

    /// 摘要屬於「轉換使用者自己的內容」，使用 Apple 提供的寬鬆過濾模式，減少誤判
    private static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)

    /// 不能使用時回傳原因，可以使用時回傳 nil
    static var unavailableReason: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "這支 iPhone 不支援 Apple Intelligence（需要 iPhone 15 Pro 以上）。"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "請到「設定 › Apple Intelligence 與 Siri」開啟 Apple Intelligence。"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence 模型還在下載中，請稍後再試。"
        default:
            return "目前無法使用 Apple Intelligence。"
        }
    }

    func summarize(transcript: String, language: TranscriptLanguage, instruction: String) async throws -> String {
        if let reason = Self.unavailableReason { throw SummaryError.appleUnavailable(reason) }

        var notes = transcript
        if language == .taiwanese {
            notes = "（這份逐字稿是從台語錄音辨識後轉寫成華語文字，用字可能不太通順。）\n" + notes
        }

        // 太長就分段整理重點，直到夠短可以一次總結
        var rounds = 0
        while notes.count > maxNotesCharacters && rounds < 4 {
            var partial: [String] = []
            for chunk in split(notes) {
                try Task.checkCancellation()
                do {
                    partial.append(try await respond(
                        "以下是一段錄音逐字稿的一部分，請用條列方式整理重點，保留重要的人名、數字、決定與待辦事項：\n\n\(chunk)",
                        maxTokens: 400
                    ))
                } catch let error as LanguageModelSession.GenerationError {
                    // 某一段被 Apple 的內容過濾擋下時，略過那一段，其他段落照常整理
                    guard case .guardrailViolation = error else { throw friendly(error) }
                    partial.append("（有一段內容被 Apple 的內容過濾略過）")
                }
            }
            notes = partial.joined(separator: "\n")
            rounds += 1
        }

        let format = instruction.isEmpty ? ClaudeSummarizer.defaultInstruction : instruction
        do {
            return try await respond("以下是錄音的內容或重點：\n\n\(notes)\n\n\(format)", maxTokens: 1_000)
        } catch let error as LanguageModelSession.GenerationError {
            throw friendly(error)
        }
    }

    private func friendly(_ error: LanguageModelSession.GenerationError) -> Error {
        switch error {
        case .guardrailViolation:
            return SummaryError.appleUnavailable("Apple 的內容過濾誤判這段內容，無法總結。請改按下方「複製給 Claude App 總結」，或在設定改用 Claude API。")
        case .unsupportedLanguageOrLocale:
            return SummaryError.appleUnavailable("Apple 裝置上模型目前不支援這個語言。請改按下方「複製給 Claude App 總結」，或在設定改用 Claude API。")
        case .exceededContextWindowSize:
            return SummaryError.appleUnavailable("內容太長，Apple 裝置上模型無法處理。請改按下方「複製給 Claude App 總結」。")
        default:
            return error
        }
    }

    private func respond(_ prompt: String, maxTokens: Int) async throws -> String {
        let session = LanguageModelSession(model: Self.model, instructions: instructions)
        let response = try await session.respond(to: prompt, options: GenerationOptions(maximumResponseTokens: maxTokens))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 依換行切段，每段不超過 chunkCharacters 個字
    private func split(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: "\n") {
            var line = line
            while line.count > chunkCharacters {
                chunks.append(String(line.prefix(chunkCharacters)))
                line = String(line.dropFirst(chunkCharacters))
            }
            if current.count + line.count > chunkCharacters, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}

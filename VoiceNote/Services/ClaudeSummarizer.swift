import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-5-5"
    case sonnet = "claude-sonnet-5-5"
    case haiku = "claude-haiku-5-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .opus: "Claude Opus 5.5（品質最好）"
        case .sonnet: "Claude Sonnet 5.5（較快、較便宜）"
        case .haiku: "Claude Haiku 5.5（最便宜）"
        }
    }

    /// Haiku 沒有伺服器端的備援模型，不能帶 fallbacks 參數
    var supportsServerFallback: Bool { self != .haiku }
}

/// 透過 Claude Messages API 產生逐字稿總結（Swift 沒有官方 SDK，所以直接呼叫 HTTP API）
struct ClaudeSummarizer {
    static let defaultInstruction = """
    請用以下格式整理：
    ## 摘要
    用 3～5 句話說明這段錄音的主要內容。
    ## 重點
    條列重要的論點、決定與數據。
    ## 待辦事項
    條列提到的待辦事項與負責人；沒有就寫「無」。
    """

    var apiKey: String
    var model: ClaudeModel

    func summarize(transcript: String, language: TranscriptLanguage, instruction: String) async throws -> String {
        var system = """
        你負責整理錄音逐字稿。請一律使用台灣繁體中文回答，內容要忠於逐字稿，不要加入逐字稿沒有的資訊。\
        逐字稿是語音辨識自動產生的，可能有同音錯字，請依上下文理解。
        """
        if language == .taiwanese {
            system += "\n這份逐字稿是從台語錄音辨識後轉寫成華語文字，用字可能不太通順。"
        }

        let userText = """
        <transcript>
        \(transcript)
        </transcript>

        \(instruction.isEmpty ? Self.defaultInstruction : instruction)
        """

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 16_000,
            "system": system,
            "messages": [["role": "user", "content": userText]],
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if model.supportsServerFallback {
            // 如果請求被安全分類器拒絕，伺服器會自動改用建議的備援模型重試
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw SummaryError.api(status: statusCode, message: apiError?.error.message ?? "未知錯誤")
        }

        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        if message.stop_reason == "refusal" { throw SummaryError.refused }
        let text = message.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw SummaryError.empty }
        return text
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
        let stop_reason: String?
    }

    private struct APIErrorResponse: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }
}

enum SummaryError: LocalizedError {
    case missingAPIKey
    case emptyTranscript
    case api(status: Int, message: String)
    case refused
    case empty

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "請先在設定頁輸入 Claude API 金鑰。"
        case .emptyTranscript: "還沒有逐字稿，請先轉錄。"
        case .api(let status, let message):
            switch status {
            case 401: "API 金鑰無效（401）。"
            case 429: "請求太頻繁或額度不足（429），請稍後再試。"
            default: "Claude API 錯誤（\(status)）：\(message)"
            }
        case .refused: "Claude 拒絕處理這份內容。"
        case .empty: "Claude 沒有回傳內容。"
        }
    }
}

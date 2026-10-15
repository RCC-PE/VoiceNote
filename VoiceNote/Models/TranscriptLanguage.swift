import Foundation

enum TranscriptLanguage: String, CaseIterable, Identifiable, Codable {
    case mandarin = "zh-TW"
    case english = "en-US"
    case taiwanese = "nan-TW"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mandarin: "國語（華語）"
        case .english: "英語"
        case .taiwanese: "台語"
        }
    }

    /// 台語用 whisper.cpp + Breeze-ASR-26；其他語言用 Apple 內建語音辨識
    var usesWhisper: Bool { self == .taiwanese }

    var locale: Locale { Locale(identifier: rawValue) }

    var note: String {
        switch self {
        case .mandarin, .english:
            "使用 Apple 內建語音辨識，在手機上離線處理。"
        case .taiwanese:
            "使用聯發科 Breeze-ASR-26 模型在手機上離線辨識，台語會轉寫成華語文字。第一次使用要先在設定裡下載模型（約 1GB）。"
        }
    }
}

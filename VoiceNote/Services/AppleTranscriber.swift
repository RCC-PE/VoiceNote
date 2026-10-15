import AVFoundation
import Speech

/// 國語、英語：使用 Apple 的 SpeechAnalyzer（iOS 26），在裝置上離線轉錄。
/// 如果該語言不支援 SpeechTranscriber，改用舊的 SFSpeechRecognizer。
struct AppleTranscriber {
    func transcribe(url: URL, locale: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return try await transcribeWithAnalyzer(url: url, locale: supported, progress: progress)
        }
        return try await transcribeWithLegacyRecognizer(url: url, locale: locale)
    }

    private func transcribeWithAnalyzer(url: URL, locale: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> [TranscriptSegment] {
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )

        // 第一次使用某語言時，系統要先下載辨識模型
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)
        let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

        let collector = Task {
            var segments: [TranscriptSegment] = []
            for try await result in transcriber.results {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let start = result.range.start.seconds
                segments.append(TranscriptSegment(start: start.isFinite ? start : 0, text: text))
                let end = result.range.end.seconds
                if duration > 0, end.isFinite { progress(min(1, end / duration)) }
            }
            return segments
        }

        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collector.value
    }

    private func transcribeWithLegacyRecognizer(url: URL, locale: Locale) async throws -> [TranscriptSegment] {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscriptionError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.unsupportedLanguage
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        // 裝置上辨識沒有一分鐘的長度限制
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    cont.resume(throwing: error)
                } else if let result, result.isFinal {
                    resumed = true
                    cont.resume(returning: [TranscriptSegment(start: 0, text: result.bestTranscription.formattedString)])
                }
            }
        }
    }
}

enum TranscriptionError: LocalizedError {
    case notAuthorized
    case unsupportedLanguage
    case modelNotInstalled
    case decodeFailed
    case whisperFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: "沒有語音辨識權限，請到「設定」App 開啟。"
        case .unsupportedLanguage: "這台裝置不支援這個語言的語音辨識。"
        case .modelNotInstalled: "還沒下載台語模型，請到設定頁下載。"
        case .decodeFailed: "無法讀取這個音檔。"
        case .whisperFailed: "台語辨識失敗。"
        }
    }
}

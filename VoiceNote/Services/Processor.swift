import Foundation
import Observation

/// 負責轉錄與總結。工作不綁在畫面上，離開頁面也會繼續執行。
@MainActor
@Observable
final class Processor {
    static let shared = Processor()

    /// 錄音 id -> 進度（0...1）
    private(set) var progress: [UUID: Double] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func isBusy(_ recording: Recording) -> Bool { tasks[recording.id] != nil }

    /// 轉錄；如果有設定 API 金鑰，接著自動總結
    func process(_ recording: Recording) {
        start(recording) {
            try await self.runTranscription(recording)
            if KeychainStore.get(SettingsKey.claudeAPIKey) != nil {
                try await self.runSummary(recording)
            }
        }
    }

    func transcribe(_ recording: Recording) {
        start(recording) { try await self.runTranscription(recording) }
    }

    func summarize(_ recording: Recording) {
        start(recording) { try await self.runSummary(recording) }
    }

    func cancel(_ recording: Recording) {
        tasks[recording.id]?.cancel()
    }

    private func start(_ recording: Recording, _ work: @escaping @MainActor () async throws -> Void) {
        guard tasks[recording.id] == nil else { return }
        let id = recording.id
        recording.errorMessage = nil
        tasks[id] = Task {
            do {
                try await work()
                recording.status = .done
            } catch is CancellationError {
                recording.status = recording.transcript.isEmpty ? .idle : .done
            } catch {
                recording.status = .failed
                recording.errorMessage = error.localizedDescription
            }
            try? recording.modelContext?.save()
            tasks[id] = nil
            progress[id] = nil
        }
    }

    private func runTranscription(_ recording: Recording) async throws {
        let id = recording.id
        recording.status = .transcribing
        progress[id] = 0
        let report: @Sendable (Double) -> Void = { value in
            Task { @MainActor in Processor.shared.progress[id] = value }
        }

        let url = recording.fileURL
        let segments: [TranscriptSegment]
        if recording.language.usesWhisper {
            let modelURL = WhisperModelManager.shared.modelURL
            segments = try await WhisperTranscriber.shared.transcribe(url: url, modelURL: modelURL, progress: report)
        } else {
            segments = try await AppleTranscriber().transcribe(url: url, locale: recording.language.locale, progress: report)
        }
        try Task.checkCancellation()
        recording.segments = segments
        try? recording.modelContext?.save()
    }

    private func runSummary(_ recording: Recording) async throws {
        guard let apiKey = KeychainStore.get(SettingsKey.claudeAPIKey) else { throw SummaryError.missingAPIKey }
        guard !recording.transcript.isEmpty else { throw SummaryError.emptyTranscript }

        recording.status = .summarizing
        progress[recording.id] = nil
        let defaults = UserDefaults.standard
        let model = ClaudeModel(rawValue: defaults.string(forKey: SettingsKey.claudeModel) ?? "") ?? .opus
        let instruction = defaults.string(forKey: SettingsKey.summaryInstruction) ?? ""

        recording.summary = try await ClaudeSummarizer(apiKey: apiKey, model: model)
            .summarize(transcript: recording.transcript, language: recording.language, instruction: instruction)
    }
}

import Foundation
import whisper

/// 台語：用 whisper.cpp 執行 Breeze-ASR-26（GGML 格式）模型
actor WhisperTranscriber {
    static let shared = WhisperTranscriber()

    /// Breeze-ASR-26 會把台語轉寫成華語文字，所以語言標記用 zh
    private let languageCode = "zh"
    /// 每次送進 whisper 的長度（5 分鐘），避免一次處理太長的音檔
    private let chunkSeconds = 300.0

    private var context: OpaquePointer?
    private var loadedModelPath: String?

    func transcribe(url: URL, modelURL: URL, progress: @escaping @Sendable (Double) -> Void) throws -> [TranscriptSegment] {
        let ctx = try loadContext(modelURL: modelURL)
        let samples = try AudioDecoder.pcm16kMono(from: url)
        let chunkSize = Int(chunkSeconds * AudioDecoder.whisperSampleRate)

        var segments: [TranscriptSegment] = []
        var offset = 0
        while offset < samples.count {
            try Task.checkCancellation()
            let end = min(offset + chunkSize, samples.count)
            guard run(ctx, samples: samples[offset..<end]) == 0 else { throw TranscriptionError.whisperFailed }

            let chunkStart = Double(offset) / AudioDecoder.whisperSampleRate
            for i in 0..<whisper_full_n_segments(ctx) {
                let text = String(cString: whisper_full_get_segment_text(ctx, i))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let t0 = Double(whisper_full_get_segment_t0(ctx, i)) / 100   // 單位是 10ms
                segments.append(TranscriptSegment(start: chunkStart + t0, text: text))
            }
            offset = end
            progress(Double(end) / Double(samples.count))
        }
        return segments
    }

    /// 釋放模型佔用的記憶體
    func unload() {
        if let context { whisper_free(context) }
        context = nil
        loadedModelPath = nil
    }

    private func loadContext(modelURL: URL) throws -> OpaquePointer {
        if let context, loadedModelPath == modelURL.path { return context }
        unload()
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw TranscriptionError.modelNotInstalled }

        var params = whisper_context_default_params()
        params.use_gpu = true   // 使用 Metal 加速
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw TranscriptionError.whisperFailed
        }
        context = ctx
        loadedModelPath = modelURL.path
        return ctx
    }

    private func run(_ ctx: OpaquePointer, samples: ArraySlice<Float>) -> Int32 {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.n_threads = Int32(max(1, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

        return languageCode.withCString { lang in
            params.language = lang
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(ctx, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
    }
}

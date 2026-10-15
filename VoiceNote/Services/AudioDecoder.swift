import AVFoundation

enum AudioDecoder {
    static let whisperSampleRate = 16_000.0

    /// 把任何 AVFoundation 能讀的音檔轉成 16kHz 單聲道 Float 取樣（whisper.cpp 需要的格式）
    static func pcm16kMono(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: whisperSampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 32_768)
        else { throw TranscriptionError.decodeFailed }

        let ratio = whisperSampleRate / inFormat.sampleRate
        let outCapacity = AVAudioFrameCount(Double(inBuffer.frameCapacity) * ratio) + 1_024
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * ratio))
        var reachedEnd = false

        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outCapacity) else {
                throw TranscriptionError.decodeFailed
            }
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
                if !reachedEnd {
                    do { try file.read(into: inBuffer) } catch { reachedEnd = true }
                    if inBuffer.frameLength == 0 { reachedEnd = true }
                }
                if reachedEnd {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let error { throw error }
            if let channel = outBuffer.floatChannelData, outBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel[0], count: Int(outBuffer.frameLength)))
            }
            if status == .endOfStream || status == .error { break }
        }
        return samples
    }
}

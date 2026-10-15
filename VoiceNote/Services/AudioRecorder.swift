import AVFoundation
import Observation

@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var isPaused = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0   // 0...1

    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: AudioStorage.newFileURL(extension: "m4a"), settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.cannotStart }

        self.recorder = recorder
        isRecording = true
        isPaused = false
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func togglePause() {
        guard let recorder else { return }
        if isPaused { recorder.record() } else { recorder.pause() }
        isPaused.toggle()
    }

    /// 停止錄音，回傳檔案位置與長度
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        isRecording = false
        isPaused = false
        level = 0
        return (recorder.url, max(duration, elapsed))
    }

    /// 取消錄音並刪除檔案
    func cancel() {
        if let result = stop() {
            try? FileManager.default.removeItem(at: result.url)
        }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }
        elapsed = recorder.currentTime
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)   // -160...0
        level = max(0, min(1, (db + 50) / 50))
    }

    enum RecorderError: LocalizedError {
        case cannotStart
        var errorDescription: String? { "無法開始錄音" }
    }
}

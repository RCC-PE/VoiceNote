import SwiftUI
import SwiftData

struct RecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.defaultLanguage) private var defaultLanguage = TranscriptLanguage.mandarin.rawValue
    @AppStorage(SettingsKey.autoProcess) private var autoProcess = true

    @State private var recorder = AudioRecorder()
    @State private var language: TranscriptLanguage = .mandarin
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Picker("語言", selection: $language) {
                    ForEach(TranscriptLanguage.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(recorder.isRecording)

                Text(language.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if language.usesWhisper && !WhisperModelManager.shared.isInstalled {
                    Label("尚未下載台語模型，錄完後請到設定頁下載再轉錄。", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Text(formatDuration(recorder.elapsed))
                    .font(.system(size: 56, weight: .light, design: .monospaced))

                LevelMeter(level: recorder.level)
                    .frame(height: 8)
                    .padding(.horizontal, 40)

                Spacer()

                HStack(spacing: 48) {
                    if recorder.isRecording {
                        Button {
                            recorder.togglePause()
                        } label: {
                            Image(systemName: recorder.isPaused ? "play.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 64))
                        }
                        Button(action: finish) {
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.red)
                        }
                    } else {
                        Button(action: start) {
                            Image(systemName: "record.circle.fill")
                                .font(.system(size: 80))
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .padding()
            .navigationTitle(recorder.isRecording ? (recorder.isPaused ? "已暫停" : "錄音中") : "新錄音")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled(recorder.isRecording)
            .onAppear { language = TranscriptLanguage(rawValue: defaultLanguage) ?? .mandarin }
            .alert("錯誤", isPresented: .constant(errorMessage != nil)) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func start() {
        Task {
            guard await recorder.requestPermission() else {
                errorMessage = "沒有麥克風權限，請到「設定」App 開啟。"
                return
            }
            do { try recorder.start() } catch { errorMessage = error.localizedDescription }
        }
    }

    private func finish() {
        guard let result = recorder.stop() else { return }
        let recording = Recording(
            title: Date.now.formatted(.dateTime.year().month().day().hour().minute()) + " 錄音",
            fileName: result.url.lastPathComponent,
            duration: result.duration,
            language: language
        )
        context.insert(recording)
        try? context.save()
        let canTranscribe = !language.usesWhisper || WhisperModelManager.shared.isInstalled
        if autoProcess && canTranscribe { Processor.shared.process(recording) }
        dismiss()
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.red.gradient)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
    }
}

import SwiftUI
import AVFoundation

struct RecordingDetailView: View {
    @Bindable var recording: Recording
    @State private var tab = ContentTab.summary
    @State private var player = AudioPlayer()
    @State private var copiedForClaude = false

    private enum ContentTab: String, CaseIterable {
        case summary = "AI 總結"
        case transcript = "逐字稿"
    }

    private var processor: Processor { .shared }
    private var busy: Bool { processor.isBusy(recording) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("標題", text: $recording.title)
                    .font(.title2.bold())

                playerControls

                HStack {
                    Picker("語言", selection: $recording.language) {
                        ForEach(TranscriptLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    .disabled(busy)
                    Spacer()
                    if busy {
                        Button("停止", role: .destructive) { processor.cancel(recording) }
                    } else {
                        Button(recording.transcript.isEmpty ? "轉逐字稿" : "重新轉錄") {
                            processor.transcribe(recording)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if recording.language.usesWhisper && !WhisperModelManager.shared.isInstalled {
                    Label("需要先到設定頁下載台語模型。", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.orange)
                }

                StatusLabel(recording: recording)

                Picker("內容", selection: $tab) {
                    ForEach(ContentTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch tab {
                case .summary: summaryView
                case .transcript: transcriptView
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
                    .disabled(recording.transcript.isEmpty)
            }
        }
        .onDisappear { player.stop() }
    }

    private var playerControls: some View {
        HStack(spacing: 12) {
            Button {
                player.toggle(url: recording.fileURL)
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 40))
            }
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: recording.duration > 0 ? min(player.currentTime / recording.duration, 1) : 0)
                Text("\(formatDuration(player.currentTime)) / \(formatDuration(recording.duration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var summaryView: some View {
        if recording.summary.isEmpty {
            VStack(spacing: 12) {
                Text(recording.transcript.isEmpty ? "請先轉出逐字稿。" : "還沒有 AI 總結。")
                    .foregroundStyle(.secondary)
                Button("產生 AI 總結", systemImage: "sparkles") { processor.summarize(recording) }
                    .buttonStyle(.borderedProminent)
                    .disabled(recording.transcript.isEmpty || busy)
                copyForClaudeAppButton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                MarkdownText(recording.summary)
                    .textSelection(.enabled)
                HStack {
                    Button("複製", systemImage: "doc.on.doc") { UIPasteboard.general.string = recording.summary }
                    Spacer()
                    Button("重新總結", systemImage: "arrow.clockwise") { processor.summarize(recording) }
                        .disabled(busy)
                }
                .font(.subheadline)
                copyForClaudeAppButton
            }
        }
    }

    /// 複製逐字稿和整理指令，貼到免費的 Claude App 就能總結，不需要 API 金鑰
    @ViewBuilder
    private var copyForClaudeAppButton: some View {
        if !recording.transcript.isEmpty {
            VStack(spacing: 4) {
                Button("複製給 Claude App 總結", systemImage: "doc.on.clipboard") {
                    UIPasteboard.general.string = ClaudeSummarizer.manualPrompt(
                        transcript: recording.transcript,
                        language: recording.language,
                        instruction: UserDefaults.standard.string(forKey: SettingsKey.summaryInstruction) ?? ""
                    )
                    copiedForClaude = true
                }
                .font(.subheadline)
                Text(copiedForClaude ? "已複製，打開 Claude App 貼上送出即可。" : "免費：複製後貼到 Claude App 或 claude.ai。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var transcriptView: some View {
        if recording.segments.isEmpty {
            Text("還沒有逐字稿。")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(recording.segments.enumerated()), id: \.offset) { _, segment in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Button(formatDuration(segment.start)) {
                            player.play(url: recording.fileURL, from: segment.start)
                        }
                        .font(.caption.monospacedDigit())
                        Text(segment.text).textSelection(.enabled)
                    }
                }
                Button("複製逐字稿", systemImage: "doc.on.doc") { UIPasteboard.general.string = recording.transcript }
                    .font(.subheadline)
            }
        }
    }

    private var shareText: String {
        var parts = [recording.title]
        if !recording.summary.isEmpty { parts.append("【AI 總結】\n" + recording.summary) }
        if !recording.transcript.isEmpty { parts.append("【逐字稿】\n" + recording.transcript) }
        return parts.joined(separator: "\n\n")
    }
}

/// 把 Claude 回傳的 Markdown 逐行顯示（標題、條列、粗體）
private struct MarkdownText: View {
    let lines: [String]
    init(_ text: String) { lines = text.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") {
                    Text(inline(trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)))
                        .font(.headline)
                        .padding(.top, 6)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(inline(String(trimmed.dropFirst(2))))
                    }
                } else if !trimmed.isEmpty {
                    Text(inline(trimmed))
                }
            }
        }
    }

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string)) ?? AttributedString(string)
    }
}

@MainActor
@Observable
final class AudioPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying { pause() } else { play(url: url, from: nil) }
    }

    func play(url: URL, from time: TimeInterval?) {
        do {
            if player?.url != url {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try AVAudioSession.sharedInstance().setActive(true)
                player = try AVAudioPlayer(contentsOf: url)
            }
            if let time { player?.currentTime = time }
            player?.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        timer?.invalidate()
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying { isPlaying = false; timer?.invalidate() }
    }
}

import SwiftUI
import SwiftData
import AVFoundation
import UniformTypeIdentifiers

struct RecordingListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Recording.createdAt, order: .reverse) private var recordings: [Recording]
    @AppStorage(SettingsKey.defaultLanguage) private var defaultLanguage = TranscriptLanguage.mandarin.rawValue
    @AppStorage(SettingsKey.autoProcess) private var autoProcess = true

    @State private var showRecorder = false
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(recordings) { recording in
                    NavigationLink(value: recording) {
                        RecordingRow(recording: recording)
                    }
                }
                .onDelete(perform: delete)
            }
            .overlay {
                if recordings.isEmpty {
                    ContentUnavailableView("還沒有錄音", systemImage: "waveform", description: Text("按下方的按鈕開始錄音，或從右上角匯入音檔。"))
                }
            }
            .navigationTitle("語音筆記")
            .navigationDestination(for: Recording.self) { RecordingDetailView(recording: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("設定", systemImage: "gearshape") { showSettings = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("匯入音檔", systemImage: "square.and.arrow.down") { showImporter = true }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showRecorder = true
                } label: {
                    Label("開始錄音", systemImage: "mic.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding()
            }
            .sheet(isPresented: $showRecorder) { RecordView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
                Task { await importFiles(result) }
            }
            .alert("匯入失敗", isPresented: .constant(importError != nil)) {
                Button("好") { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        do {
            for source in try result.get() {
                let accessing = source.startAccessingSecurityScopedResource()
                defer { if accessing { source.stopAccessingSecurityScopedResource() } }

                let ext = source.pathExtension.isEmpty ? "m4a" : source.pathExtension
                let destination = AudioStorage.newFileURL(extension: ext)
                try FileManager.default.copyItem(at: source, to: destination)
                let duration = (try? await AVURLAsset(url: destination).load(.duration).seconds) ?? 0

                let recording = Recording(
                    title: source.deletingPathExtension().lastPathComponent,
                    fileName: destination.lastPathComponent,
                    duration: duration.isFinite ? duration : 0,
                    language: TranscriptLanguage(rawValue: defaultLanguage) ?? .mandarin
                )
                context.insert(recording)
                try? context.save()
                if autoProcess { Processor.shared.process(recording) }
            }
        } catch {
            importError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            Processor.shared.cancel(recording)
            try? FileManager.default.removeItem(at: recording.fileURL)
            context.delete(recording)
        }
        try? context.save()
    }
}

private struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title).font(.headline).lineLimit(1)
            HStack(spacing: 8) {
                Text(recording.createdAt, format: .dateTime.month().day().hour().minute())
                Text(formatDuration(recording.duration))
                Text(recording.language.displayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            StatusLabel(recording: recording)
        }
        .padding(.vertical, 2)
    }
}

struct StatusLabel: View {
    let recording: Recording

    var body: some View {
        switch recording.status {
        case .transcribing:
            if let value = Processor.shared.progress[recording.id] {
                ProgressView(value: value) { Text("轉錄中… \(Int(value * 100))%").font(.caption) }
            } else {
                Label("轉錄中…", systemImage: "waveform").font(.caption).foregroundStyle(.blue)
            }
        case .summarizing:
            Label("AI 總結中…", systemImage: "sparkles").font(.caption).foregroundStyle(.purple)
        case .failed:
            Label(recording.errorMessage ?? "處理失敗", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red).lineLimit(2)
        case .idle, .done:
            EmptyView()
        }
    }
}

func formatDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = total % 3600 / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

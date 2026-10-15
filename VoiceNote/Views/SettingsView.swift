import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.summaryEngine) private var summaryEngine = SummaryEngine.apple.rawValue
    @AppStorage(SettingsKey.claudeModel) private var claudeModel = ClaudeModel.opus.rawValue
    @AppStorage(SettingsKey.summaryInstruction) private var summaryInstruction = ""
    @AppStorage(SettingsKey.defaultLanguage) private var defaultLanguage = TranscriptLanguage.mandarin.rawValue
    @AppStorage(SettingsKey.autoProcess) private var autoProcess = true
    @AppStorage(SettingsKey.taiwaneseModelURL) private var taiwaneseModelURL = ""

    @State private var apiKey = KeychainStore.get(SettingsKey.claudeAPIKey) ?? ""
    @State private var showModelImporter = false
    private var models: WhisperModelManager { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("總結方式", selection: $summaryEngine) {
                        ForEach(SummaryEngine.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    if summaryEngine == SummaryEngine.apple.rawValue, let reason = AppleSummarizer.unavailableReason {
                        Text(reason).font(.footnote).foregroundStyle(.orange)
                    }
                } header: {
                    Text("AI 總結")
                } footer: {
                    Text("Apple 裝置上模型免費、離線，需要支援 Apple Intelligence 的 iPhone。不論選哪一種，逐字稿頁面都有「複製給 Claude App 總結」按鈕，可以貼到免費的 Claude App 使用。")
                }

                Section {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("模型", selection: $claudeModel) {
                        ForEach(ClaudeModel.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                } header: {
                    Text("Claude API（選填）")
                } footer: {
                    Text("總結方式選 Claude API 時才需要。到 platform.claude.com 申請 API 金鑰並儲值，費用依用量計算；Haiku 5.5 總結一小時錄音不到 US$0.01。金鑰只存在這支手機的 Keychain。")
                }

                Section {
                    TextEditor(text: $summaryInstruction)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if summaryInstruction.isEmpty {
                                Text("留空會使用預設格式（摘要、重點、待辦事項）。也可以改成例如「整理成會議紀錄」。")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } header: {
                    Text("總結格式（選填）")
                }

                Section("轉錄") {
                    Picker("預設語言", selection: $defaultLanguage) {
                        ForEach(TranscriptLanguage.allCases) { Text($0.displayName).tag($0.rawValue) }
                    }
                    Toggle("錄完或匯入後自動轉錄並總結", isOn: $autoProcess)
                }

                Section {
                    if models.isInstalled {
                        LabeledContent("狀態", value: "已安裝 \(models.installedSize ?? "")")
                        Button("刪除模型", role: .destructive) { models.delete() }
                    } else if let progress = models.downloadProgress {
                        ProgressView(value: progress) { Text("下載中… \(Int(progress * 100))%") }
                        Button("取消下載", role: .destructive) { models.cancelDownload() }
                    } else {
                        TextField("模型檔網址（.bin）", text: $taiwaneseModelURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                        Button("下載模型") {
                            if let url = URL(string: taiwaneseModelURL.trimmingCharacters(in: .whitespaces)) {
                                models.download(from: url)
                            }
                        }
                        .disabled(URL(string: taiwaneseModelURL)?.scheme?.hasPrefix("http") != true)
                        Button("從「檔案」匯入模型") { showModelImporter = true }
                    }
                    if let error = models.errorMessage {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                } header: {
                    Text("台語模型（Breeze-ASR-26）")
                } footer: {
                    Text("台語辨識使用聯發科開源的 Breeze-ASR-26 模型（Apache-2.0），whisper.cpp 的 GGML 格式，約 1GB，建議用 Wi-Fi 下載。到 Hugging Face 的 Breeze-ASR-26 GGML 頁面複製 .bin 檔的下載網址（網址中含 /resolve/main/）貼到上面；也可以先在電腦下載，再用 AirDrop 或「檔案」App 匯入。")
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onChange(of: apiKey) {
                KeychainStore.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: SettingsKey.claudeAPIKey)
            }
            .fileImporter(isPresented: $showModelImporter, allowedContentTypes: [.data]) { result in
                if case .success(let url) = result { models.importModel(from: url) }
            }
        }
    }
}

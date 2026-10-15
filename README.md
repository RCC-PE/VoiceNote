# 語音筆記（VoiceNote）iOS App

錄音或匯入音檔，轉成逐字稿，再用 Claude 產生 AI 總結。支援國語、英語、台語。

## 功能

- **錄音**：可以暫停/繼續，螢幕鎖定後也會繼續錄。
- **匯入音檔**：從「檔案」App 選 m4a、mp3、wav 等格式，可以一次選多個。
- **逐字稿**：每一段都有時間戳記，點時間就從那裡開始播放。
  - 國語、英語：Apple SpeechAnalyzer（iOS 26），在手機上離線處理，免費。
  - 台語：聯發科開源的 Breeze-ASR-26 模型，透過 whisper.cpp 在手機上離線執行，台語會轉寫成**華語文字**。
- **AI 總結**：可用免費的 Apple 裝置上模型、複製到免費的 Claude App，或付費的 Claude API。預設格式是摘要、重點、待辦事項，可以在設定頁自訂。
- 複製、分享逐字稿與總結；重新轉錄、重新總結。

## 需要的東西

- Mac，安裝 Xcode 26 以上
- iPhone，iOS 26 以上
  - 台語模型約 1GB，建議用 iPhone 15 Pro 以上（8GB 記憶體）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- Claude API 金鑰：到 <https://platform.claude.com> 申請

## 建置步驟

1. **下載 whisper.cpp 框架**
   到 <https://github.com/ggml-org/whisper.cpp/releases> 下載 `whisper-v1.9.2-xcframework.zip`（v1.9.3 之後的版本沒有附這個檔案），解壓後把 `whisper.xcframework` 放到專案的 `Frameworks/` 資料夾：
   ```
   VoiceNote/
   ├── Frameworks/whisper.xcframework
   ├── VoiceNote/...
   └── project.yml
   ```
2. **產生 Xcode 專案**
   ```bash
   cd VoiceNote
   xcodegen
   open VoiceNote.xcodeproj
   ```
3. **設定簽署**
   在 Xcode 點選 VoiceNote target，到 *Signing & Capabilities* 選你的 Team（免費 Apple ID 也可以），並把 Bundle Identifier 改成自己的，例如 `com.yourname.voicenote`。
4. **裝到 iPhone**
   用線接上 iPhone，選擇你的裝置，按 ▶︎ 執行。第一次要到 iPhone 的「設定 > 一般 > VPN 與裝置管理」信任開發者，並開啟「開發者模式」。

> 用免費 Apple ID 簽署的 App 7 天後會失效，要重新從 Xcode 安裝一次。付費開發者帳號（每年 US$99）則有一年效期，也可以用 TestFlight 安裝。

## 沒有 Mac：用 GitHub 雲端編譯 + Windows 安裝

每次推送到 `main`，GitHub Actions 會在雲端 Mac 上自動編譯出 `VoiceNote.ipa`（未簽署）。

1. 到 repo 的 **Actions** 頁籤，打開最新一次成功的編譯，在下方 **Artifacts** 下載 `VoiceNote-ipa` 並解壓縮。
2. Windows 電腦先安裝：
   - iTunes（Apple 官網版，不是 Microsoft Store 版）：<https://www.apple.com/itunes/download/win64>
   - iCloud for Windows 7.21（非 Store 版）：<https://updates.cdn-apple.com/2020/windows/001-39935-20200911-1A70AA56-F448-11EA-8CC0-99D41950005E/iCloudSetup.exe>
     （SHA-256：`4CFD20D13CDCE2B5C435F2DDAF4EE4C81D976461846BF3B954E8AF6CBCDEB9F7`）
   - Sideloadly：<https://sideloadly.io/>
3. **iTunes 和 iCloud 都要用同一個 Apple ID 登入**（iTunes 是從選單「帳號 › 登入」）。沒登入 iTunes 的話，Sideloadly 會出現 `GSA returned a non-plist response (HTTP 503)` 錯誤。
4. 用傳輸線接上 iPhone，在 Sideloadly 選 `VoiceNote.ipa`、輸入 Apple ID，按 Start。設定維持 Local Anisette 即可（Remote 要付費）。
5. iPhone 上開啟「設定 › 隱私權與安全性 › 開發者模式」，並到「設定 › 一般 › VPN 與裝置管理」信任自己的 Apple ID。
6. 免費 Apple ID 安裝的 App **每 7 天**要用 Sideloadly 重新安裝一次，資料會保留。

## 第一次使用

1. 打開 App，點左上角 ⚙️ 進入設定，貼上 Claude API 金鑰。
2. **要用台語的話**：
   - 到 Hugging Face 搜尋 **Breeze-ASR-26 GGML**（例如 `weemed/Breeze-ASR-26-GGML`），在 Files 頁籤找到 `.bin` 模型檔（Q5_0 準確度較好，Q4_0 檔案較小）。
   - 對檔案名稱按右鍵複製下載連結（網址中含 `/resolve/main/`），貼到設定頁的「模型檔網址」再按「下載模型」。
   - 也可以先在電腦下載，再用 AirDrop 傳到 iPhone，然後按「從『檔案』匯入模型」。
3. 第一次用國語或英語轉錄時，iOS 會自動下載系統的語音辨識模型，需要網路。

## 關於台語辨識

- Apple 內建的語音辨識**不支援台語**，所以台語另外用 Breeze-ASR-26。
- 這個模型會把台語轉寫成**華語文字**（例如「你食飽未」會寫成「你吃飽了沒」），不是台文漢字或台羅拼音。用來做筆記和總結比較方便，但不是逐字的台文紀錄。
- 根據媒體報導的測試，平均字元錯誤率約 30%，比國語辨識高。內容會有錯字，Claude 總結時會依上下文修正理解。
- 這是大型模型，在手機上跑得比國語辨識慢很多，速度依機型而定（我沒有實測過），長錄音可能要花上和錄音差不多長的時間。處理期間請讓 App 留在前景。
- 要做到台文漢字或台羅輸出，可以改接國家的「Taiwan Tongues ASR」自架服務（<https://github.com/adi-gov-tw/Taiwan-Tongues-ASR-CE>），但需要自己準備有 GPU 的伺服器。

## AI 總結的三種方式

| 方式 | 費用 | 說明 |
|---|---|---|
| Apple 裝置上模型（預設） | 免費 | 離線執行，需要支援 Apple Intelligence 的 iPhone（iPhone 15 Pro 以上）並開啟 Apple Intelligence。品質比 Claude 差一些，長錄音會先分段整理再總結。 |
| 複製給 Claude App | 免費 | 逐字稿頁面按「複製給 Claude App 總結」，貼到免費的 Claude App 或 claude.ai 送出。需要手動貼上一次。 |
| Claude API | 依用量付費 | 全自動、品質最好。需要到 platform.claude.com 儲值。一小時錄音的逐字稿約 2～3 萬 token：Haiku 5.5 一次不到 US$0.01，Opus 5.5 約 US$0.1～0.2。 |

## 程式架構

```
VoiceNote/
├── VoiceNoteApp.swift            App 進入點（SwiftData）
├── Models/
│   ├── Recording.swift           錄音資料（標題、逐字稿、總結…）
│   └── TranscriptLanguage.swift  語言選項：國語 / 英語 / 台語
├── Services/
│   ├── AudioRecorder.swift       錄音
│   ├── AppleTranscriber.swift    國語、英語轉錄（SpeechAnalyzer）
│   ├── WhisperTranscriber.swift  台語轉錄（whisper.cpp + Breeze-ASR-26）
│   ├── AudioDecoder.swift        音檔轉成 16kHz 取樣給 whisper
│   ├── WhisperModelManager.swift 台語模型下載、匯入、刪除
│   ├── ClaudeSummarizer.swift    呼叫 Claude API 產生總結
│   ├── KeychainStore.swift       API 金鑰存在 Keychain
│   └── Processor.swift           管理轉錄、總結的背景工作
└── Views/
    ├── RecordingListView.swift   首頁列表、匯入
    ├── RecordView.swift          錄音畫面
    ├── RecordingDetailView.swift 播放、逐字稿、總結
    └── SettingsView.swift        設定
```

## 已知限制

- 這份程式碼是在沒有 Xcode 的環境寫的，**還沒實際編譯過**。第一次建置可能會有少量編譯錯誤需要修正，主要可能出在 iOS 26 的新 API（SpeechAnalyzer）。
- 台語音檔以 5 分鐘為一段處理，分段的地方可能會切到一個詞。
- API 金鑰存在手機上，只適合自己使用。要上架給別人用，需要另外架後端來保管金鑰。

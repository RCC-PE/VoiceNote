import Foundation
import Observation

/// 管理台語模型檔（Breeze-ASR-26 GGML）的下載、匯入與刪除
@MainActor
@Observable
final class WhisperModelManager {
    static let shared = WhisperModelManager()

    private(set) var isInstalled = false
    private(set) var downloadProgress: Double?   // nil 表示沒有在下載
    var errorMessage: String?

    private var downloadTask: Task<Void, Never>?

    let modelURL: URL = {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("breeze-asr-26.bin")
    }()

    init() { refresh() }

    var installedSize: String? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: modelURL.path))?[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    func refresh() {
        isInstalled = FileManager.default.fileExists(atPath: modelURL.path)
    }

    func download(from remote: URL) {
        guard downloadProgress == nil else { return }
        errorMessage = nil
        downloadProgress = 0
        let destination = modelURL
        downloadTask = Task {
            do {
                try await FileDownloader.download(from: remote, to: destination) { value in
                    Task { @MainActor in
                        if WhisperModelManager.shared.downloadProgress != nil {
                            WhisperModelManager.shared.downloadProgress = value
                        }
                    }
                }
            } catch is CancellationError {
            } catch {
                errorMessage = "下載失敗：\(error.localizedDescription)"
            }
            downloadProgress = nil
            refresh()
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
    }

    /// 從「檔案」App 匯入已下載好的模型檔（例如先在電腦下載再傳到手機）
    func importModel(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try? FileManager.default.removeItem(at: modelURL)
            try FileManager.default.copyItem(at: url, to: modelURL)
            errorMessage = nil
        } catch {
            errorMessage = "匯入失敗：\(error.localizedDescription)"
        }
        refresh()
    }

    func delete() {
        Task { await WhisperTranscriber.shared.unload() }
        try? FileManager.default.removeItem(at: modelURL)
        refresh()
    }
}

/// 用 URLSessionDownloadTask 下載大檔案並回報進度
private final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?

    private init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    static func download(from remote: URL, to destination: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let downloader = FileDownloader(destination: destination, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.downloadTask(with: remote)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                downloader.continuation = cont
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(URLError(.badServerResponse)))
            return
        }
        // 暫存檔在這個方法結束後就會被刪除，所以要在這裡搬走
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(()))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure((error as? URLError)?.code == .cancelled ? CancellationError() : error))
        }
    }
}

import Foundation
import SwiftData

struct TranscriptSegment: Codable, Hashable {
    var start: Double   // 秒
    var text: String
}

enum ProcessingStatus: String, Codable {
    case idle, transcribing, summarizing, done, failed
}

@Model
final class Recording {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var fileName: String
    var languageRaw: String
    var transcript: String
    var segmentsData: Data?
    var summary: String
    var statusRaw: String
    var errorMessage: String?

    init(title: String, fileName: String, duration: Double, language: TranscriptLanguage) {
        self.id = UUID()
        self.title = title
        self.createdAt = .now
        self.duration = duration
        self.fileName = fileName
        self.languageRaw = language.rawValue
        self.transcript = ""
        self.summary = ""
        self.statusRaw = ProcessingStatus.idle.rawValue
    }

    var language: TranscriptLanguage {
        get { TranscriptLanguage(rawValue: languageRaw) ?? .mandarin }
        set { languageRaw = newValue.rawValue }
    }

    var status: ProcessingStatus {
        get { ProcessingStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    var segments: [TranscriptSegment] {
        get {
            guard let segmentsData else { return [] }
            return (try? JSONDecoder().decode([TranscriptSegment].self, from: segmentsData)) ?? []
        }
        set {
            segmentsData = try? JSONEncoder().encode(newValue)
            transcript = newValue.map(\.text).joined(separator: "\n")
        }
    }

    var fileURL: URL { AudioStorage.directory.appendingPathComponent(fileName) }
}

enum AudioStorage {
    static var directory: URL {
        let url = URL.documentsDirectory.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func newFileURL(extension ext: String) -> URL {
        directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }
}

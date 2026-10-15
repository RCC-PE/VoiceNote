import SwiftUI
import SwiftData

@main
struct VoiceNoteApp: App {
    var body: some Scene {
        WindowGroup {
            RecordingListView()
        }
        .modelContainer(for: Recording.self)
    }
}

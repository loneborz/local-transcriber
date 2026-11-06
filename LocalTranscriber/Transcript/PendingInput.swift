import Foundation

// What a job was created from.
nonisolated enum JobSource {
    case file(URL)
    case youtube(videoID: String, url: URL)
}

// An input that waits for its language (LTR-72). Session only: an imported file
// that was not started is forgotten on quit. A recording's audio is already saved
// in its entry folder, and the library offers it again after a relaunch (`offer`).
// It has no engine: its job takes the saved preference when it is enqueued (LTR-82).
nonisolated struct PendingInput: Identifiable {
    let id = UUID()
    let source: JobSource
    let recording: (folder: URL, startedAt: Date)?

    var name: String {
        switch source {
        case .file(let url): url.lastPathComponent
        case .youtube(let videoID, _): "YouTube · \(videoID)"
        }
    }
}

nonisolated extension [PendingInput] {
    // Queue admission (LTR-82): removes the input and returns it with the engine
    // preference read now, which its job keeps. Nil, with the list unchanged, when
    // the input is no longer here or that engine cannot run.
    mutating func admit(
        _ id: PendingInput.ID, whisperInstalled: @autoclosure () -> Bool, defaults: UserDefaults = .standard
    ) -> (input: PendingInput, engine: TranscriptionEngine)? {
        let engine = TranscriptionEngine.preferred(in: defaults)
        guard engine.canStartJob(whisperInstalled: whisperInstalled()),
              let index = firstIndex(where: { $0.id == id }) else { return nil }
        return (remove(at: index), engine)
    }
}

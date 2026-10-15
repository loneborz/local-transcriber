import Foundation

// The rules that connect processing to reviewing. Pure, so they are tested; the
// views only ask them.

// What the workspace needs to know about one job.
nonisolated struct QueueEntry: Equatable, Sendable {
    var id: UUID
    // Jobs added while nothing was waiting or running start a new batch.
    var batch: Int
    // Complete and saved: it is in the library and needs nothing more. A Complete
    // job whose save failed is not settled; it still needs the user.
    var isSettled: Bool
    // Waiting, downloading or transcribing.
    var isUnfinished: Bool
}

// New Transcription is a fresh working area, not a view of everything the
// session ever did. The queue keeps every job (nothing is deleted or cleared);
// the workspace shows a window over it, starting at `firstVisibleBatch`.
nonisolated enum QueueWorkspace {
    // Settled jobs of batches before the window are hidden (their transcripts
    // live in the library). Everything else stays, in queue order: running work,
    // failed jobs and jobs whose save failed must remain reachable for Retry or
    // Save Transcript, however old their batch.
    static func visible(_ entries: [QueueEntry], firstVisibleBatch: Int) -> [UUID] {
        entries.filter { !($0.isSettled && $0.batch < firstVisibleBatch) }.map(\.id)
    }

    // The user starts fresh (leaves a transcript for New Transcription): every
    // batch that has nothing running is put behind them. A batch still being
    // processed stays whole, completed results included.
    static func firstVisibleBatch(afterStartingFresh entries: [QueueEntry]) -> Int {
        if let running = entries.filter(\.isUnfinished).map(\.batch).min() { return running }
        return (entries.map(\.batch).max() ?? 0) + 1
    }

    // New files begin a new visible batch of their own.
    static func firstVisibleBatch(forNewBatch batch: Int) -> Int { batch }
}

nonisolated enum AutoOpen {
    // A finished job opens its transcript on its own only when it is the whole
    // batch (several files must not make the view jump at every completion) and
    // the user is not reading another transcript (that was a deliberate choice).
    static func shouldRequest(batchJobCount: Int, userIsReviewingTranscript: Bool) -> Bool {
        batchJobCount == 1 && !userIsReviewingTranscript
    }
}

// A request to open the transcript a job saved. It names the URL the save
// reported (the file actually written, collision suffix included), never a
// guessed name, and is answered only from a library scan that was started after
// the save.
nonisolated struct PendingOpen: Equatable, Sendable {
    var savedURL: URL

    enum Outcome: Equatable, Sendable {
        case open(LibraryTranscript)
        // The library does not list it (saved elsewhere, scan failed) or the user
        // has taken over: forget the request.
        case drop
    }

    func resolve(in index: LibraryJoin.Index, userIsReviewingTranscript: Bool) -> Outcome {
        guard !userIsReviewingTranscript,
              let item = LibraryJoin.item(forSavedURL: savedURL, in: index) else { return .drop }
        return .open(item)
    }
}

// The sidebar always has a selection. The List reports nil when the selected
// row is Command-clicked (a deselect); that must not empty the workspace.
nonisolated enum SidebarSelectionRule {
    static func next<S>(current: S?, proposed: S?) -> S? { proposed ?? current }
}

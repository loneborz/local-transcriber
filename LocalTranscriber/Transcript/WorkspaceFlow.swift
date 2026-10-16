import Foundation

// The rules that connect processing to reviewing. Pure, so they are tested; the
// views only ask them.

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

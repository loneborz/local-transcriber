import Foundation

// The one rule the sidebar's selection follows. Pure, so it is tested.

nonisolated enum SidebarSelectionRule {
    static func next<S>(current: S?, proposed: S?) -> S? { proposed ?? current }
}

// Whether a window opens the transcript its own request produced (LTR-72). It is
// armed when the user chooses a language in that window; the last transcript saved
// for it since then opens once nothing is pending, waiting or running and the
// library lists it. Any navigation by the user disarms it, so a job that finishes
// in the background never takes the window elsewhere; an opened one is not opened again.
nonisolated struct ReviewAutoOpen {
    private(set) var isArmed = false
    private(set) var target: URL?

    mutating func languageChosen() {
        isArmed = true
    }

    mutating func userNavigated() {
        isArmed = false
        target = nil
    }

    mutating func saved(_ transcript: URL) {
        if isArmed { target = transcript }
    }

    // The transcript to open now, if any. A failed-only request leaves nothing to open.
    mutating func transcriptToOpen(isQuiet: Bool, isListed: (URL) -> Bool) -> URL? {
        guard isArmed, isQuiet, let target, isListed(target) else { return nil }
        isArmed = false
        self.target = nil
        return target
    }
}

// The language menu's Recent section (LTR-72): the newest choice first, each one
// once, at most `limit`; the oldest drops out (and is listed under All Languages again).
nonisolated enum RecentChoices {
    static let limit = 3

    static func choosing<T: Equatable>(_ choice: T, in recent: [T], limit: Int = limit) -> [T] {
        Array(([choice] + recent.filter { $0 != choice }).prefix(limit))
    }
}

import Foundation

// How far into the audio the recognizer has delivered results. This is coverage of
// the audio, not an estimate of the work or the time left: no ETA is derived from
// it, and nothing here looks at the clock. The position never moves backwards, so
// late or overlapping results cannot make a progress bar step back.
nonisolated struct RecognitionProgress: Equatable, Sendable {
    private(set) var position: TimeInterval
    private(set) var total: TimeInterval

    init?(position: TimeInterval, total: TimeInterval) {
        guard total.isFinite, total > 0, position.isFinite else { return nil }
        self.total = total
        self.position = min(max(0, position), total)
    }

    // Takes a new report; a position behind the current one, or one that is not a
    // number, changes nothing.
    mutating func report(position newPosition: TimeInterval, total newTotal: TimeInterval) {
        if newTotal.isFinite, newTotal > 0 { total = newTotal }
        guard newPosition.isFinite else { return }
        position = min(max(position, newPosition), total)
    }

    // 0...1 of the audio covered.
    var coverage: Double { position / total }

    // "00:42:18": hours, minutes, seconds, whole seconds rounded down.
    static func clock(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < Double(Int.max) else { return "--:--:--" }
        let whole = Int(seconds)
        return String(format: "%02d:%02d:%02d", whole / 3600, (whole % 3600) / 60, whole % 60)
    }
}

import Foundation

// Engine-independent raw recognition data: what a recognizer reported, in the
// order it reported it, with the times it reported. It knows no Apple type, so
// another engine adapter can produce the same shape. Times are seconds on the
// recognizer's timeline and are kept as emitted (possibly negative, reversed
// or non-finite); nothing here repairs or invents a time. `nil` means the
// engine gave none.
nonisolated struct TimedRecognition: Sendable, Equatable {
    var results: [RecognitionResult] = []
}

// One result of the recognizer, with the range it reported for the whole
// result and the units it is made of.
nonisolated struct RecognitionResult: Sendable, Equatable {
    var start: Double?
    var end: Double?
    var units: [RecognitionUnit]
}

nonisolated struct RecognitionUnit: Sendable, Equatable {
    enum Kind: String, Sendable, Codable {
        // Text with at least one letter or digit.
        case word
        // Text without any letter or digit: marks, symbols, whitespace. Engines
        // report these with a zero-width range or none.
        case punctuation
        // The text of a whole result that the engine gave no finer timing for.
        case segment
    }

    var text: String
    var kind: Kind
    var start: Double?
    var end: Double?

    static func classify(_ text: String) -> Kind {
        text.contains { $0.isLetter || $0.isNumber } ? .word : .punctuation
    }
}

nonisolated enum TimingGranularity: String, Sendable, Codable {
    // Units carry their own times.
    case word
    // Only whole results carry times.
    case segment
    // No usable time at all.
    case none
}

nonisolated extension TimedRecognition {
    // What the data actually offers, never what the engine is capable of.
    var granularity: TimingGranularity {
        let hasFiniteRange = { (start: Double?, end: Double?) in
            (start?.isFinite ?? false) && (end?.isFinite ?? false)
        }
        if results.contains(where: { $0.units.contains { hasFiniteRange($0.start, $0.end) } }) {
            return .word
        }
        return results.contains { hasFiniteRange($0.start, $0.end) } ? .segment : .none
    }
}

// A time range that can drive review lines. Anything else is ignored for
// that purpose (and kept as emitted in the raw data):
// non-finite, negative start, end before start, or a start past a known duration.
// An end past the duration is kept as emitted.
nonisolated enum TimingValidity {
    static func usableRange(start: Double?, end: Double?, duration: Double?) -> ClosedRange<Double>? {
        guard let start, let end, start.isFinite, end.isFinite, start >= 0, end >= start else {
            return nil
        }
        if let duration, duration.isFinite, start > duration { return nil }
        return start...end
    }
}

nonisolated struct ReviewLine: Sendable, Equatable {
    var text: String
    var start: Double?
    var end: Double?
}

// Tuning values, not product guarantees: change them (and bump the algorithm
// version) without retranscribing, because lines are derived from raw units.
nonisolated struct ReviewLineOptions: Sendable, Equatable {
    // A pause longer than this between two units starts a new line.
    var maxPause: Double = 1.2
    // A line never grows past this span from its first to its last time.
    var maxLineDuration: Double = 12
    var sentenceEnders: Set<Character> = [".", "!", "?", "…"]
}

// Derives readable, seekable lines from raw units. Pure and deterministic: the
// same input gives the same lines, in recognition order (never re-sorted).
nonisolated enum ReviewLines {
    // Increase when the grouping rules change.
    static let algorithmVersion = 1

    static func group(
        _ recognition: TimedRecognition,
        duration: Double? = nil,
        options: ReviewLineOptions = ReviewLineOptions()
    ) -> [ReviewLine] {
        var lines: [ReviewLine] = []
        var current = Builder()

        for result in recognition.results {
            let resultRange = TimingValidity.usableRange(start: result.start, end: result.end, duration: duration)
            let hasTimedUnit = result.units.contains {
                TimingValidity.usableRange(start: $0.start, end: $0.end, duration: duration) != nil
            }

            for unit in result.units {
                let text = unit.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }

                // A result without any timed unit is segment-level data: its
                // own reported range stands in for its units.
                let range = TimingValidity.usableRange(start: unit.start, end: unit.end, duration: duration)
                    ?? (hasTimedUnit ? nil : resultRange)

                if unit.kind != .punctuation, current.shouldBreak(before: range, options: options) {
                    lines.append(current.line)
                    current = Builder()
                }
                current.append(unit, text: text, range: range)
            }
        }
        if current.hasText { lines.append(current.line) }
        return lines
    }

    private struct Builder {
        var text = ""
        var start: Double?
        var end: Double?

        var hasText: Bool { !text.isEmpty }
        var line: ReviewLine { ReviewLine(text: text, start: start, end: end) }

        func shouldBreak(before range: ClosedRange<Double>?, options: ReviewLineOptions) -> Bool {
            guard hasText else { return false }
            if let last = text.last, options.sentenceEnders.contains(last) { return true }
            guard let range else { return false }
            if let end, range.lowerBound - end > options.maxPause { return true }
            if let start, range.upperBound - start > options.maxLineDuration { return true }
            return false
        }

        mutating func append(_ unit: RecognitionUnit, text unitText: String, range: ClosedRange<Double>?) {
            // Marks attach to the preceding text unless the engine emitted
            // whitespace in front of them.
            let attaches = unit.kind == .punctuation && unit.text.first?.isWhitespace != true
            text += (text.isEmpty || attaches ? "" : " ") + unitText
            guard let range else { return }
            start = start ?? range.lowerBound
            end = max(end ?? range.upperBound, range.upperBound)
        }
    }
}

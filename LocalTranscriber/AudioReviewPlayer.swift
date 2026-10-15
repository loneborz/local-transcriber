import AVFoundation
import Foundation
import Observation
import os

// The one audio player of the window. It plays the audio of the transcript that
// is open in the Review view, and nothing else:
//  - it never plays by itself (opening a transcript only prepares it);
//  - a new transcript, New Transcription or a closing window stops it (the
//    owner calls `stop()`; the view model below also ignores stale loads);
//  - every load is tagged with a generation, so a slow load that finishes after
//    the selection moved on can neither become ready nor start playing.
// Which file belongs to a transcript is decided by AudioResolution (pure); this
// type only opens it.
@MainActor @Observable
final class AudioReviewPlayer {
    enum Phase: Equatable {
        case none
        case loading
        case ready
        case unavailable(AudioAvailability)
    }

    // The transcript this state belongs to; views show the player only for it.
    private(set) var itemID: LibraryTranscript.ID?
    private(set) var phase = Phase.none
    private(set) var isPlaying = false
    // Reached the end: the playhead rests at the end until Play (from the start) or a seek.
    private(set) var hasFinished = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    // Index of the review line being spoken (LineTimeline); nil when none.
    private(set) var activeLine: Int?
    // A failure while playing (the file vanished, a decoding error).
    private(set) var playbackError: String?

    @ObservationIgnored private var timeline = LineTimeline(lines: [])
    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var failureObserver: NSObjectProtocol?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fileName = ""

    private static let log = Logger(subsystem: "nl.wavesweb.LocalTranscriber", category: "player")

    var isReady: Bool { phase == .ready }

    // MARK: loading

    // Prepares the audio of `item` (stopping whatever was loaded before). Never
    // plays. File and metadata access happens off the main thread.
    func prepare(for item: LibraryTranscript, transcriptDuration: Double?, lines: [ReviewLine]) async {
        stop()
        generation += 1
        let mine = generation
        itemID = item.id
        timeline = LineTimeline(lines: lines)
        phase = .loading

        guard let url = AudioResolution.candidateURL(for: item) else {
            phase = .unavailable(.notKept)
            return
        }
        fileName = url.lastPathComponent
        let name = fileName
        let outcome = await Task.detached(priority: .userInitiated) {
            await Self.inspect(url, transcriptDuration: transcriptDuration)
        }.value

        // The selection moved on while loading: this result belongs to nobody.
        guard mine == generation, !Task.isCancelled else { return }

        switch outcome {
        case .unavailable(let availability):
            phase = .unavailable(availability)
            Self.log.info("player: \(name, privacy: .public) unavailable")
        case .ready(let seconds):
            install(url: url, duration: seconds)
            phase = .ready
            Self.log.info("player: \(name, privacy: .public) ready, \(seconds, format: .fixed(precision: 2), privacy: .public) s")
        }
    }

    private enum Inspection: Sendable {
        case ready(Double)
        case unavailable(AudioAvailability)
    }

    private nonisolated static func inspect(_ url: URL, transcriptDuration: Double?) async -> Inspection {
        let name = url.lastPathComponent
        guard FileManager.default.fileExists(atPath: url.path) else { return .unavailable(.missing(name)) }
        let asset = AVURLAsset(url: url)
        do {
            let (seconds, playable) = try await asset.load(.duration, .isPlayable)
            guard playable else { return .unavailable(.unreadable(name)) }
            let length = CMTimeGetSeconds(seconds)
            return AudioResolution.durationsAgree(audio: length, transcript: transcriptDuration)
                ? .ready(length) : .unavailable(.mismatch(name))
        } catch {
            return .unavailable(.unreadable(name))
        }
    }

    private func install(url: URL, duration seconds: Double) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        duration = seconds
        currentTime = 0
        activeLine = nil
        isPlaying = false
        hasFinished = false
        playbackError = nil

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didFinish() }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didFail() }
        }
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in self?.didFail() }
        }
    }

    // MARK: transport

    func play() {
        guard phase == .ready, let player else { return }
        playbackError = nil
        if hasFinished { seek(to: 0) }
        player.play()
        isPlaying = true
        Self.log.info("player: play \(self.fileName, privacy: .public)")
    }

    func pause() {
        player?.pause()
        if isPlaying { Self.log.info("player: pause \(self.fileName, privacy: .public)") }
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    // Moves the playhead without changing whether it is playing.
    func seek(to seconds: Double) {
        guard phase == .ready, let player, seconds.isFinite else { return }
        let target = min(max(seconds, 0), duration)
        currentTime = target
        activeLine = timeline.activeLine(at: target)
        hasFinished = target >= duration
        // Zero tolerance: AAC otherwise lands on the nearest packet boundary.
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // A click on a timestamp: seek to the line and play (the owner-approved
    // contract of LTR-44 AC 14). Returns false for an untimed or out-of-range line.
    @discardableResult
    func play(from line: ReviewLine) -> Bool {
        guard phase == .ready,
              let target = LineTimeline.seekTarget(for: line, audioDuration: duration) else { return false }
        seek(to: target)
        play()
        return true
    }

    // Pauses and forgets everything: another transcript, New Transcription,
    // a closing window. Invalidates any load still in flight.
    func stop() {
        generation += 1
        if isPlaying { Self.log.info("player: stop \(self.fileName, privacy: .public)") }
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        statusObservation?.invalidate()
        statusObservation = nil
        for observer in [endObserver, failureObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        failureObserver = nil
        player?.pause()
        player = nil
        itemID = nil
        phase = .none
        isPlaying = false
        hasFinished = false
        currentTime = 0
        duration = 0
        activeLine = nil
        playbackError = nil
    }

    // MARK: callbacks

    private func tick(_ seconds: Double) {
        guard seconds.isFinite, phase == .ready else { return }
        let time = min(max(seconds, 0), duration)
        if abs(time - currentTime) >= 0.05 { currentTime = time }
        let line = timeline.activeLine(at: time)
        if line != activeLine { activeLine = line }
        if isPlaying, let player, player.rate == 0, !hasFinished { isPlaying = false }
    }

    private func didFinish() {
        isPlaying = false
        hasFinished = true
        currentTime = duration
        Self.log.info("player: finished \(self.fileName, privacy: .public)")
    }

    // The file vanished or cannot be decoded mid-review: say so, never crash.
    private func didFail() {
        guard phase == .ready else { return }
        let name = fileName
        player?.pause()
        isPlaying = false
        playbackError = "Playback stopped: the audio “\(name)” can’t be played."
        Self.log.error("player: failed \(name, privacy: .public)")
    }
}

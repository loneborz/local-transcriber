import Foundation
import Observation

struct MediaInfo {
    let type: String
    let duration: String
    let fileSize: String
}

@MainActor @Observable
final class TranscriptionJob: Identifiable {
    enum State {
        case waiting
        case transcribing(TranscriptionPhase?)
        case complete(Transcript, processingDuration: Duration)
        case failed(String)
    }

    let id = UUID()
    let url: URL
    // Editable only while Waiting; read once when the job starts.
    var locale: Locale
    var mediaInfo: MediaInfo?
    var state: State = .waiting
    var savedTranscriptURL: URL?
    // Set when transcription succeeded but the automatic save did not.
    var saveError: String?

    init(url: URL, locale: Locale) {
        self.url = url
        self.locale = locale
    }

    var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }
}

@MainActor @Observable
final class BatchQueue {
    private(set) var jobs: [TranscriptionJob] = []
    let destination = OutputDestination()
    private var isRunning = false

    var isProcessing: Bool { isRunning }
    var hasWaitingJobs: Bool { jobs.contains(where: \.isWaiting) }

    // Adds jobs in the Waiting state, each owning the given locale. Nothing
    // runs until `start` is called; if a batch is already running, its runner
    // picks the new jobs up.
    func enqueue(_ urls: [URL], locale: Locale) -> [TranscriptionJob] {
        let newJobs = urls.map { TranscriptionJob(url: $0, locale: locale) }
        jobs.append(contentsOf: newJobs)
        return newJobs
    }

    // Only a Waiting job can be removed; the runner re-scans `jobs` on every
    // pass, so a removed job never runs. Source media is never touched.
    func remove(_ job: TranscriptionJob) {
        guard job.isWaiting else { return }
        jobs.removeAll { $0.id == job.id }
    }

    // Idle means no batch is running, so any mix of Waiting, Complete and
    // Failed jobs can be cleared. Never cancels an active job.
    var canClear: Bool { !jobs.isEmpty && !isRunning }

    func clear() {
        guard canClear else { return }
        jobs.removeAll()
    }

    func start() {
        guard !isRunning, hasWaitingJobs else { return }
        isRunning = true
        Task { await run() }
    }

    // Re-checks for waiting jobs on every pass, so jobs appended mid-run are
    // picked up; `isRunning` is cleared with no suspension point after the
    // last check.
    private func run() async {
        while let job = jobs.first(where: \.isWaiting) {
            await process(job)
        }
        isRunning = false
    }

    private func process(_ job: TranscriptionJob) async {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let locale = job.locale
        job.state = .transcribing(nil)

        do {
            let transcript = try await TranscriptionService.transcribe(
                url: job.url,
                locale: locale,
                onPhaseChange: { job.state = .transcribing($0) }
            )
            job.state = .complete(transcript, processingDuration: startedAt.duration(to: clock.now))
            save(transcript, for: job)
        } catch {
            job.state = .failed(error.localizedDescription)
        }
    }

    // A failed save never fails the job: it stays Complete with its transcript
    // in memory, and the error is recorded for the manual Save fallback.
    private func save(_ transcript: Transcript, for job: TranscriptionJob) {
        do {
            job.savedTranscriptURL = try destination.write(
                TranscriptMarkdownRenderer.render(transcript),
                baseName: job.url.deletingPathExtension().lastPathComponent
            )
            job.saveError = nil
        } catch {
            job.saveError = error.localizedDescription
        }
    }
}

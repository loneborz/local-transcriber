import Foundation
import Observation

struct MediaInfo {
    let type: String
    let duration: String
    let fileSize: String
}

// What a job was created from. An invalid source is a job that has already
// failed, so it stays visible in the queue instead of silently disappearing.
enum JobSource {
    case file(URL)
    case youtube(videoID: String, url: URL)
    case invalid(input: String, reason: String)
}

@MainActor @Observable
final class TranscriptionJob: Identifiable {
    enum State {
        case waiting
        case downloading
        case transcribing(TranscriptionPhase?)
        case complete(Transcript, processingDuration: Duration)
        case failed(String)
    }

    let id = UUID()
    let source: JobSource
    // Editable only while Waiting; read once when the job starts.
    var locale: Locale
    var mediaInfo: MediaInfo?
    // Set once a YouTube source has been resolved and downloaded.
    var metadata: SourceMetadata?
    var state: State = .waiting
    var savedTranscriptURL: URL?
    // Set when transcription succeeded but the automatic save did not.
    var saveError: String?

    init(source: JobSource, locale: Locale) {
        self.source = source
        self.locale = locale
        if case .invalid(_, let reason) = source {
            state = .failed(reason)
        }
    }

    var displayName: String {
        switch source {
        case .file(let url): url.lastPathComponent
        case .youtube(let videoID, _): metadata?.title ?? "YouTube · \(videoID)"
        case .invalid(let input, _): input
        }
    }

    var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }
}

@MainActor @Observable
final class BatchQueue {
    private(set) var jobs: [TranscriptionJob] = []
    // UserDefaults key of the "save YouTube links as source packages" mode.
    static let sourcePackageModeKey = "sourcePackageMode"

    let destination = OutputDestination()
    private var isRunning = false

    var isProcessing: Bool { isRunning }
    var hasWaitingJobs: Bool { jobs.contains(where: \.isWaiting) }

    // Adds jobs in the Waiting state (invalid sources start Failed), each
    // owning the given locale. Nothing runs until `start` is called; if a batch
    // is already running, its runner picks the new jobs up.
    func enqueue(_ sources: [JobSource], locale: Locale) -> [TranscriptionJob] {
        let newJobs = sources.map { TranscriptionJob(source: $0, locale: locale) }
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
        switch job.source {
        case .file(let url):
            await transcribeAndSave(job, mediaURL: url)
        case .youtube(let videoID, let url):
            // Resolved and downloaded only now, at job start. A failure here
            // fails this job alone; the runner moves on to the next one.
            job.state = .downloading
            let acquired: AcquiredAudio
            do {
                acquired = try await YouTubeAcquirer.acquire(videoID: videoID, url: url)
            } catch {
                job.state = .failed(error.localizedDescription)
                return
            }
            defer { try? FileManager.default.removeItem(at: acquired.directory) }
            job.metadata = acquired.metadata
            await transcribeAndSave(job, mediaURL: acquired.audioURL)
        case .invalid(_, let reason):
            job.state = .failed(reason)
        }
    }

    private func transcribeAndSave(_ job: TranscriptionJob, mediaURL: URL) async {
        let clock = ContinuousClock()
        let startedAt = clock.now
        let locale = job.locale
        job.state = .transcribing(nil)

        do {
            let transcript = try await TranscriptionService.transcribe(
                url: mediaURL,
                locale: locale,
                onPhaseChange: { job.state = .transcribing($0) }
            )
            job.state = .complete(transcript, processingDuration: startedAt.duration(to: clock.now))
            save(transcript, for: job, mediaURL: mediaURL)
        } catch {
            job.state = .failed(error.localizedDescription)
        }
    }

    // A failed save never fails the job: it stays Complete with its transcript
    // in memory, and the error is recorded for the manual Save fallback.
    private func save(_ transcript: Transcript, for job: TranscriptionJob, mediaURL: URL) {
        do {
            if UserDefaults.standard.bool(forKey: Self.sourcePackageModeKey),
               case .youtube(let videoID, _) = job.source,
               let metadata = job.metadata {
                // Source package: only for YouTube jobs. The audio is copied out
                // of the temporary directory before the caller removes it.
                job.savedTranscriptURL = try destination.writePackage(
                    videoID: videoID,
                    audio: mediaURL,
                    manifest: SourcePackageManifest(
                        metadata: metadata,
                        transcriptionLocale: transcript.localeIdentifier
                    ).encoded(),
                    transcript: TranscriptMarkdownRenderer.render(transcript, source: metadata)
                )
            } else {
                job.savedTranscriptURL = try destination.write(
                    TranscriptMarkdownRenderer.render(transcript),
                    baseName: mediaURL.deletingPathExtension().lastPathComponent
                )
            }
            job.saveError = nil
        } catch {
            job.saveError = error.localizedDescription
        }
    }
}

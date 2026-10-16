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
    // Set when the Markdown was saved but its timing sidecar was not. The job
    // and the Markdown are unaffected; this is only a notice.
    var sidecarWarning: String?
    // Which batch added this job (see BatchQueue.enqueue). Only the queue view
    // uses it, to keep earlier finished work out of the way.
    var batch = 0
    // Whether the automatic save used the source-package presentation. Fixed
    // when the save is attempted, so later changes to the preference cannot
    // change what Copy or the manual Save writes for this job.
    var exportedAsPackage = false
    // Set for a recording: the entry folder that already holds its audio, and
    // when the recording started (the entry's creation time).
    var recording: (folder: URL, startedAt: Date)?

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

    // The entry folder's name: the media file's name, or a video's title.
    func entryName(mediaURL: URL) -> String {
        if case .youtube = source, let title = metadata?.title, !title.isEmpty { return title }
        return mediaURL.deletingPathExtension().lastPathComponent
    }

    // When the entry was created: the recording's start, a video's acquisition,
    // or, for an imported file, now (the save).
    var createdAt: Date {
        if let recording { return recording.startedAt }
        if case .youtube = source, let acquired = metadata?.acquiredAt { return acquired }
        return .now
    }

    var isWaiting: Bool {
        if case .waiting = state { return true }
        return false
    }

    // Waiting, downloading or transcribing.
    var isUnfinished: Bool {
        switch state {
        case .waiting, .downloading, .transcribing: true
        case .complete, .failed: false
        }
    }

    // The one place that decides how this job's transcript is presented:
    // automatic save, manual Save and Copy all use it.
    func markdown(for transcript: Transcript) -> String {
        TranscriptMarkdownRenderer.render(transcript, source: exportedAsPackage ? metadata : nil)
    }

    // A rejected link fails the same way every time, so only failures of a
    // real source are worth retrying.
    var canRetry: Bool {
        guard case .failed = state else { return false }
        if case .invalid = source { return false }
        return true
    }
}

struct BatchSummary {
    var succeeded = 0
    var failed = 0
    var mediaDuration: TimeInterval = 0
    var processingDuration: Duration = .zero

    var hasFinishedJobs: Bool { succeeded + failed > 0 }
}

@MainActor @Observable
final class BatchQueue {
    private(set) var jobs: [TranscriptionJob] = []
    // UserDefaults key of the "save YouTube links as source packages" mode.
    static let sourcePackageModeKey = "sourcePackageMode"

    let destination: OutputDestination

    init(destination: OutputDestination) {
        self.destination = destination
    }
    private var isRunning = false
    private var batchCounter = 0
    // The batch the newest jobs belong to; changes when a new batch begins.
    var currentBatch: Int { batchCounter }

    var isProcessing: Bool { isRunning }
    var hasWaitingJobs: Bool { jobs.contains(where: \.isWaiting) }
    var waitingCount: Int { jobs.filter(\.isWaiting).count }

    // Only Waiting jobs are editable; active, Complete and Failed jobs keep
    // the language they started with.
    func applyLocale(_ locale: Locale) {
        for job in jobs where job.isWaiting {
            job.locale = locale
        }
    }

    // Adds jobs in the Waiting state (invalid sources start Failed), each
    // owning the given locale. Nothing runs until `start` is called; if a batch
    // is already running, its runner picks the new jobs up.
    func enqueue(_ sources: [JobSource], locale: Locale) -> [TranscriptionJob] {
        let newJobs = sources.map { TranscriptionJob(source: $0, locale: locale) }
        // Files added while nothing is waiting or running begin a new batch; files
        // added to unfinished work join it.
        if !jobs.contains(where: \.isUnfinished) { batchCounter += 1 }
        for job in newJobs { job.batch = batchCounter }
        jobs.append(contentsOf: newJobs)
        return newJobs
    }

    // Only a Waiting job can be removed; the runner re-scans `jobs` on every
    // pass, so a removed job never runs. Source media is never touched.
    func remove(_ job: TranscriptionJob) {
        guard job.isWaiting else { return }
        jobs.removeAll { $0.id == job.id }
    }

    // Totals over the jobs currently in the queue. Duration and processing
    // time come from Complete jobs only; downloading is not processing.
    var summary: BatchSummary { summary(of: jobs) }

    func summary(of jobs: [TranscriptionJob]) -> BatchSummary {
        var summary = BatchSummary()
        for job in jobs {
            switch job.state {
            case .complete(let transcript, let processingDuration):
                summary.succeeded += 1
                summary.mediaDuration += transcript.duration ?? 0
                summary.processingDuration += processingDuration
            case .failed:
                summary.failed += 1
            default:
                break
            }
        }
        return summary
    }

    // Returns one Failed job to Waiting. Complete jobs are never touched, so
    // a retry cannot repeat finished work. The caller starts the queue.
    func retry(_ job: TranscriptionJob) {
        guard job.canRetry else { return }
        job.metadata = nil
        job.saveError = nil
        job.sidecarWarning = nil
        job.exportedAsPackage = false
        job.state = .waiting
    }

    // The library renamed or moved a saved transcript: the jobs that saved it
    // follow the file.
    func relocate(from old: URL, to new: URL) {
        let oldPath = old.standardizedFileURL.path
        for job in jobs where job.savedTranscriptURL?.standardizedFileURL.path == oldPath {
            job.savedTranscriptURL = new
        }
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
        // Decided before the write, so it is also set when the write fails.
        var package: SourceMetadata?
        if UserDefaults.standard.bool(forKey: Self.sourcePackageModeKey),
           case .youtube = job.source,
           let metadata = job.metadata {
            package = metadata
        }
        job.exportedAsPackage = package != nil

        job.sidecarWarning = nil
        var metadataWarning: String?

        do {
            let saved = try TranscriptSidecar.saveWithSidecar(
                transcript,
                markdown: job.markdown(for: transcript),
                writeMarkdown: { markdown in
                    // One folder per job, named after the media (or the video's
                    // title). A source package also keeps the audio, copied out of
                    // the temporary directory before the caller removes it.
                    let written = try destination.writeEntry(
                        baseName: job.entryName(mediaURL: mediaURL),
                        existingFolder: job.recording?.folder,
                        markdown: markdown,
                        createdAt: job.createdAt,
                        audio: package == nil ? nil : mediaURL,
                        manifest: try package.map {
                            try SourcePackageManifest(
                                metadata: $0, transcriptionLocale: transcript.localeIdentifier
                            ).encoded()
                        }
                    )
                    metadataWarning = written.metadataWarning
                    job.savedTranscriptURL = written.markdown
                    return written.markdown
                },
                // The sidecar goes next to the file actually written.
                writeSidecar: { try destination.writeSidecar($0, besides: $1) }
            )
            job.saveError = nil
            job.sidecarWarning = [saved.sidecarWarning, metadataWarning].compactMap { $0 }.joined(separator: "\n")
            if job.sidecarWarning?.isEmpty == true { job.sidecarWarning = nil }
        } catch {
            job.saveError = error.localizedDescription
        }
    }
}

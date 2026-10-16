import SwiftUI
import AppKit

// What the window can do for a job. The Processing section only draws; saving,
// copying and opening need the window (panels, selection, notices).
struct ProcessingActions {
    // The action that opens the job's transcript in the library, if it is listed there.
    var openTarget: (TranscriptionJob) -> (() -> Void)?
    // Saved, but not into the folder the library is listing.
    var savedElsewhere: (TranscriptionJob) -> Bool
    var save: (TranscriptionJob) -> Void
    // Returns whether the pasteboard accepted the text.
    var copy: (TranscriptionJob) -> Bool
    var retry: (TranscriptionJob) -> Void
    var remove: (TranscriptionJob) -> Void
    var start: () -> Void
    var applyLanguage: () -> Void
    var clearFinished: () -> Void
    var canStart: Bool
    var canChangeLanguage: Bool
    var defaultLanguageTitle: String
}

// The sidebar's Processing section: the jobs of the app-wide queue, compact, with
// the state of each, real progress where the recognizer gives it, and the actions
// the old queue page offered. Shown whenever there is something to see or do.
struct ProcessingSection: View {
    let queue: BatchQueue
    let jobs: [TranscriptionJob]
    let actions: ProcessingActions

    @State private var isExpanded = true
    @State private var showsAll = false
    @State private var openDetails: Set<UUID> = []

    // A long batch must not push the library out of view.
    private static let compactCount = 4

    var body: some View {
        Section(isExpanded: $isExpanded) {
            if queue.unstartedCount > 0 {
                Button(action: actions.start) {
                    Label("Start \(queue.unstartedCount)", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.wineFill)
                .controlSize(.small)
                .disabled(!actions.canStart)
                .selectionDisabled()
                .help(actions.canStart
                      ? "Start the waiting jobs, one after the other."
                      : "Jobs can’t start while recording or without an output folder.")
            }
            ForEach(shownJobs) { job in
                ProcessingRow(
                    job: job,
                    actions: actions,
                    isDetailOpen: Binding(
                        get: { openDetails.contains(job.id) },
                        set: { open in
                            if open { openDetails.insert(job.id) } else { openDetails.remove(job.id) }
                        }))
            }
            if jobs.count > Self.compactCount {
                Button(showsAll ? "Show fewer" : "Show \(jobs.count - Self.compactCount) more") {
                    showsAll.toggle()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .selectionDisabled()
            }
        } header: {
            header
        }
    }

    // Active work first, then what needs attention, then what waits.
    private var orderedJobs: [TranscriptionJob] {
        func rank(_ job: TranscriptionJob) -> Int {
            switch job.state {
            case .downloading, .transcribing: 0
            case .failed: 1
            case .complete: job.savedTranscriptURL == nil ? 1 : 3
            case .waiting: 2
            }
        }
        return jobs.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    private var shownJobs: [TranscriptionJob] {
        showsAll ? orderedJobs : Array(orderedJobs.prefix(Self.compactCount))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text("Processing")
                if queue.isProcessing {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("Processing")
                }
                Spacer()
                Menu {
                    Button("Apply Language to All Waiting") { actions.applyLanguage() }
                        .disabled(queue.waitingCount < 2 || !actions.canChangeLanguage)
                    Button("Clear Finished") { actions.clearFinished() }
                        .disabled(!queue.canClear)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Processing actions")
                .accessibilityLabel("Processing actions")
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    // "1 running · 2 waiting · 1 failed", in plain counts.
    private var summary: String {
        var running = 0, waiting = 0, failed = 0
        for job in jobs {
            switch job.state {
            case .downloading, .transcribing: running += 1
            case .waiting: waiting += 1
            case .failed: failed += 1
            case .complete: if job.savedTranscriptURL == nil { failed += 1 }
            }
        }
        let parts = [
            running > 0 ? "\(running) running" : nil,
            waiting > 0 ? "\(waiting) waiting" : nil,
            failed > 0 ? "\(failed) need attention" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? "Finishing" : parts.joined(separator: " · ")
    }
}

private struct ProcessingRow: View {
    let job: TranscriptionJob
    let actions: ProcessingActions
    @Binding var isDetailOpen: Bool

    // Confirmation lives only in this row; every click restarts the reset task.
    @State private var copied = false
    @State private var copyClicks = 0

    var body: some View {
        DisclosureGroup(isExpanded: $isDetailOpen) {
            details
        } label: {
            summary
        }
    }

    // MARK: collapsed row

    private var summary: some View {
        HStack(alignment: .top, spacing: 8) {
            statusIcon
                .frame(width: 14, height: 14)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(stage)
                    .font(.caption)
                    .foregroundStyle(isFailure ? Color.red : Color.secondary)
                    .lineLimit(isFailure ? 2 : 1)
                progress
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var progress: some View {
        switch job.state {
        case .downloading, .transcribing:
            if let progress = job.progress {
                ProgressView(value: progress.coverage)
                    .controlSize(.small)
                Text("\(RecognitionProgress.clock(progress.position)) / \(RecognitionProgress.clock(progress.total))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Audio recognized so far. This is coverage of the audio, not an estimate of the time left.")
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                if let startedAt = job.startedAt {
                    HStack(spacing: 4) {
                        Text("Elapsed")
                        Text(startedAt, style: .timer)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }

    private var isFailure: Bool {
        switch job.state {
        case .failed: true
        case .complete: job.savedTranscriptURL == nil
        default: false
        }
    }

    // The accurate stage, in the words of the processing steps.
    private var stage: String {
        switch job.state {
        case .waiting: job.isStarted ? "Waiting for its turn" : "Ready to start"
        case .downloading: "Acquiring media…"
        case .transcribing(let phase): phase?.label ?? "Transcribing…"
        case .complete:
            job.savedTranscriptURL == nil ? "Not saved" : "Complete"
        case .failed(let message): "Failed · \(message)"
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.state {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading, .transcribing:
            Image(systemName: "waveform").foregroundStyle(Color.accentColor)
        case .complete:
            job.savedTranscriptURL == nil
                ? Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                : Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    // MARK: details

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            languageLine

            if let metadata = job.metadata {
                Text(metadata.detailText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let mediaInfo = job.mediaInfo {
                Text("\(mediaInfo.type) · \(mediaInfo.duration) · \(mediaInfo.fileSize)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = job.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if case .complete(let transcript, let processingDuration) = job.state {
                Text("\(transcript.characterCount) characters · \(Self.completionMetrics(for: transcript, processingDuration: processingDuration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if job.savedTranscriptURL == nil, let saveError = job.saveError {
                    Text("Not saved: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let sidecarWarning = job.sidecarWarning {
                    Text(sidecarWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let saved = job.savedTranscriptURL {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([saved])
                    } label: {
                        Text("Saved · \(saved.deletingPathExtension().lastPathComponent)")
                            .font(.caption)
                            .underline(true, color: Theme.emphasis.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(saved.lastPathComponent) in Finder")
                }
                if actions.savedElsewhere(job) {
                    Text("Not in the current library: saved to another output folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            buttons
        }
        .padding(.vertical, 2)
    }

    // The language can only change while the job waits.
    @ViewBuilder
    private var languageLine: some View {
        if job.isWaiting {
            Picker("Language", selection: language) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        } else {
            Text(language.wrappedValue.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var language: Binding<TranscriptionLanguage> {
        Binding(
            get: { TranscriptionLanguage.allCases.first { $0.locale == job.locale } ?? .english },
            set: { job.locale = $0.locale }
        )
    }

    private var buttons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { buttonItems }
            VStack(alignment: .leading, spacing: 6) { buttonItems }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var buttonItems: some View {
        if let open = actions.openTarget(job) {
            Button("Open", action: open)
                .help("Open this transcript")
                .accessibilityLabel("Open transcript")
        }
        if case .complete = job.state {
            Button {
                copied = actions.copy(job)
                copyClicks += 1
            } label: {
                ZStack {
                    Text("Copied").hidden()
                    Text(copied ? "Copied" : "Copy")
                }
            }
            .help("Copy transcript as Markdown")
            .accessibilityLabel("Copy transcript as Markdown")
            .accessibilityValue(copied ? "Copied" : "")
            .task(id: copyClicks) {
                guard copied else { return }
                try? await Task.sleep(for: .milliseconds(1500))
                if !Task.isCancelled { copied = false }
            }
            if job.saveError != nil, job.savedTranscriptURL == nil {
                Button("Save Transcript…") { actions.save(job) }
            }
        }
        if job.canRetry {
            Button("Retry") { actions.retry(job) }
        }
        // The original, as the queue page's job name offered.
        switch job.source {
        case .file(let url):
            Button("Show Original") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .help("Reveal the original file in Finder")
        case .youtube(_, let url):
            Button("Open Video") { NSWorkspace.shared.open(url) }
                .help("Open on YouTube")
        case .invalid:
            EmptyView()
        }
        if job.isWaiting {
            Button("Remove", role: .destructive) { actions.remove(job) }
                .accessibilityLabel("Remove from queue")
        }
    }

    // MARK: formatting

    static func completionMetrics(for transcript: Transcript, processingDuration: Duration) -> String {
        let processingTime = MetricsFormat.processingDuration(processingDuration)
        var text = "Processed in \(processingTime)"

        if let mediaDuration = transcript.duration.flatMap(MetricsFormat.mediaDuration) {
            text = "\(mediaDuration) processed in \(processingTime)"
        }

        if let realtimeSpeed = transcript.duration.flatMap({
            MetricsFormat.realtimeSpeed(mediaDuration: $0, processingDuration: processingDuration)
        }) {
            text += " · \(realtimeSpeed) realtime"
        }

        return text
    }
}

// Shared by the per-job details so every figure is formatted one way.
enum MetricsFormat {
    static func mediaDuration(_ seconds: TimeInterval) -> String? {
        guard seconds.isFinite, seconds > 0 else { return nil }

        if seconds < 60 {
            let tenths = (seconds * 10).rounded() / 10
            return "\(number(tenths, decimals: tenths.rounded() == tenths ? 0 : 1))s"
        }

        guard seconds < Double(Int.max) else { return nil }
        let wholeSeconds = Int(seconds)
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds % 3600) / 60
        return hours > 0
            ? "\(hours)h \(twoDigits(minutes))m"
            : "\(minutes)m"
    }

    static func realtimeSpeed(mediaDuration: TimeInterval, processingDuration: Duration) -> String? {
        guard mediaDuration.isFinite, mediaDuration > 0 else { return nil }
        let elapsedSeconds = seconds(processingDuration)
        guard elapsedSeconds > 0 else { return nil }

        let speed = mediaDuration / elapsedSeconds
        guard speed.isFinite, speed > 0 else { return nil }

        let rounded = speed >= 20 ? speed.rounded() : (speed * 10).rounded() / 10
        let decimals = speed < 20 && rounded.rounded() != rounded ? 1 : 0
        return "\(number(rounded, decimals: decimals))×"
    }

    static func processingDuration(_ duration: Duration) -> String {
        let seconds = seconds(duration)
        if seconds < 60 {
            let tenths = (seconds * 10).rounded() / 10
            return "\(number(tenths, decimals: tenths.rounded() == tenths ? 0 : 1))s"
        }

        guard seconds < Double(Int.max) else { return "\(number(seconds, decimals: 0))s" }
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(twoDigits(minutes))m \(twoDigits(remainingSeconds))s"
        }
        return "\(minutes)m \(remainingSeconds)s"
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        String(
            format: decimals == 0 ? "%.0f" : "%.1f",
            locale: Locale(identifier: "en_US_POSIX"),
            value
        )
    }

    private static func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

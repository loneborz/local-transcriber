import SwiftUI
import AppKit

// What the window can do for the job. The Processing section only draws; saving,
// copying and dismissing need the window (panels, notices, confirmation).
struct ProcessingActions {
    var save: (TranscriptionJob) -> Void
    // Returns whether the pasteboard accepted the text.
    var copy: (TranscriptionJob) -> Bool
    var retry: (TranscriptionJob) -> Void
    var dismiss: (TranscriptionJob) -> Void
}

// The sidebar's Processing section: the job the app is working on, the jobs that
// wait their turn (their language is chosen, LTR-72) and those that need attention,
// with stage, real progress where the recognizer gives it, elapsed time, and the
// recovery actions. The section is there only while there are jobs.
struct ProcessingSection: View {
    let queue: BatchQueue
    let jobs: [TranscriptionJob]
    let actions: ProcessingActions

    @State private var isExpanded = true
    @State private var openJob: UUID?

    var body: some View {
        Section(isExpanded: $isExpanded) {
            ForEach(jobs) { job in
                ProcessingRow(
                    job: job,
                    actions: actions,
                    isDetailOpen: Binding(get: { openJob == job.id }, set: { openJob = $0 ? job.id : nil }))
            }
        } header: {
            header
        }
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
            }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }

    private var summary: String {
        var parts: [String] = []
        if jobs.contains(where: { !$0.isWaiting && !$0.isSettled }) { parts.append("1 running") }
        let waiting = jobs.filter(\.isWaiting).count
        if waiting > 0 { parts.append("\(waiting) waiting") }
        let settled = jobs.filter(\.isSettled)
        if !settled.isEmpty {
            parts.append(settled.allSatisfy { $0.savedTranscriptURL != nil } ? "Saved, with a warning" : "Needs attention")
        }
        return parts.joined(separator: " · ")
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
                // The language this job was accepted with, not the current preference.
                Text("\(language) · \(Text(stage).foregroundStyle(isFailure ? Color.red : Color.secondary))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        case .waiting: "Waiting"
        case .downloading: "Acquiring media…"
        case .transcribing(let phase): phase?.label ?? "Transcribing…"
        case .complete:
            job.savedTranscriptURL == nil ? "Not saved" : "Saved, with a warning"
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
                    .help(message)
                    .lineLimit(8)
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
            }

            buttons
        }
        .padding(.vertical, 2)
        // Show whole messages (errors, metrics) instead of cutting them to one line.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var language: String {
        TranscriptionLanguage.allCases.first { $0.locale == job.locale }?.title ?? job.locale.identifier
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
        }
        // Removes a job that has not started, failed or was not saved (the window asks
        // before an unsaved transcript is dropped).
        switch job.state {
        case .waiting, .failed, .complete:
            Button("Dismiss") { actions.dismiss(job) }
                .help("Remove this job from Processing")
        default:
            EmptyView()
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

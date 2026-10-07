import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var pasteLinks: (() -> Void)?
}

struct ContentView: View {
    @State private var queue = BatchQueue()
    @State private var recorder = Recorder()
    @State private var isTargeted = false
    @State private var isQueueTargeted = false
    @State private var showsRecordSetup = false
    // Include microphone for app recordings; kept for this session only.
    @State private var includesMicrophoneWithApp = true
    @AppStorage("defaultLanguage") private var selectedLanguage = TranscriptionLanguage.english
    @AppStorage(BatchQueue.sourcePackageModeKey) private var savesSourcePackages = false
    @State private var notice: String?

    private let supportedExtensions = [
        "mp4",
        "mov",
        "m4a",
        "mp3",
        "wav"
    ]

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
        }
        .background(.ultraThinMaterial)
        .frame(minWidth: 640, minHeight: 420)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            addDroppedFiles(urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .focusedSceneValue(\.pasteLinks, pasteFromClipboard)
        .onAppear { recorder.refreshApps() }
        // Closing the window must not leave a recording running unseen.
        .onDisappear { recorder.cancel() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            recorder.refreshApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            recorder.refreshApps()
        }
    }

    @ViewBuilder
    private var content: some View {
        if queue.jobs.isEmpty {
            // Three groups: mark + tagline, drop target, Record. The column is
            // centered so a taller window does not leave a loose empty lower third.
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    WaveformBars(isAnimating: false)

                    Text("Media in. Markdown out.")
                        .font(.title3.weight(.semibold))
                }

                VStack(spacing: 16) {
                    // The drop target is also the file picker.
                    Button(action: chooseFiles) {
                        VStack(spacing: 4) {
                            Text(isTargeted ? "Drop to add" : "Drop media here")
                                .font(.callout)
                            Text("or choose files… · ⌘V to paste a YouTube link")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 330, height: 84)
                        .background(
                            isTargeted
                                ? Color.accentColor.opacity(0.12)
                                : Color.primary.opacity(0.045),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    isTargeted
                                        ? Color.accentColor.opacity(0.8)
                                        : Color.secondary.opacity(0.22),
                                    lineWidth: isTargeted ? 1.5 : 0.5
                                )
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(!recorder.isIdle)
                    .scaleEffect(isTargeted ? 0.98 : 1)
                    .animation(.easeOut(duration: 0.18), value: isTargeted)

                    VStack(spacing: 8) {
                        if recorder.isIdle {
                            recordButton
                                .controlSize(.large)
                        } else {
                            recordingStatus(compact: false)
                        }

                        recorderMessages

                        if let notice {
                            Text(notice)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420, maxHeight: .infinity)
            .padding(40)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                queueActionBar

                recorderMessages

                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                VStack(spacing: 6) {
                    // Clear belongs to the queue, so it heads the queue with the summary.
                    HStack(alignment: .firstTextBaseline) {
                        summaryView
                        Spacer()
                        if queue.canClear {
                            Button("Clear") {
                                queue.clear()
                                notice = nil
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(minHeight: 16)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(queue.jobs) { job in
                                JobRow(job: job, onSave: {
                                    if case .complete(let transcript, _) = job.state {
                                        saveTranscript(transcript, for: job)
                                    }
                                }, onRemove: {
                                    queue.remove(job)
                                }, onRetry: {
                                    queue.retry(job)
                                    startQueue()
                                })

                                if job.id != queue.jobs.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        if isTargeted || isQueueTargeted {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
                        }
                    }
                    // ScrollView is a platform view and does not pass drops up to the
                    // window-level destination, so it is a drop target itself.
                    .contentShape(Rectangle())
                    .dropDestination(for: URL.self) { urls, _ in
                        addDroppedFiles(urls)
                    } isTargeted: { targeted in
                        isQueueTargeted = targeted
                    }
                }
            }
            .frame(maxWidth: 720, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // Inputs on the left, Transcribe on the right so it can come and go
    // without moving them. A running recording replaces the whole row.
    private var queueActionBar: some View {
        HStack(spacing: 8) {
            WaveformBars(isAnimating: queue.isProcessing)
                .scaleEffect(0.55)
                .frame(width: 38, height: 28)
                .padding(.trailing, 4)

            if recorder.isIdle {
                Button("Add Files", action: chooseFiles)
                recordButton

                Spacer()

                if !queue.isProcessing && queue.waitingCount > 0 {
                    Button("Transcribe \(queue.waitingCount)", action: startQueue)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                recordingStatus(compact: true)
                Spacer()
            }
        }
        .controlSize(.large)
        .frame(minHeight: 28)
    }

    private var recordButton: some View {
        Button("Record") {
            recorder.refreshApps()
            showsRecordSetup = true
        }
        .disabled(recorder.unsavedRecording != nil)
        .popover(isPresented: $showsRecordSetup, arrowEdge: .bottom) {
            recordSetup
        }
    }

    // Record is one more input: the finished recording is saved to the output
    // folder and then queued exactly like a dropped file.
    private var recordSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Record audio")
                .font(.headline)

            Picker("Source:", selection: $recorder.selectedAppID) {
                Text("Microphone").tag(String?.none)
                Divider()
                ForEach(recorder.apps) { app in
                    Text(app.name).tag(String?.some(app.id))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            if recorder.selectedAppID != nil {
                Toggle("Include microphone", isOn: $includesMicrophoneWithApp)
                    .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    showsRecordSetup = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Start Recording", action: startRecording)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private func startRecording() {
        showsRecordSetup = false
        // Microphone as the source means microphone only.
        recorder.includesMicrophone = recorder.selectedAppID == nil || includesMicrophoneWithApp
        Task {
            await recorder.record(to: queue.destination) { addRecording($0) }
        }
    }

    // Stacked under the hero when the list is empty, one row above the queue otherwise.
    @ViewBuilder
    private func recordingStatus(compact: Bool) -> some View {
        switch recorder.state {
        case .idle:
            EmptyView()
        case .starting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting recording…")
                    .foregroundStyle(.secondary)
            }
        case .recording(let since):
            let layout = compact
                ? AnyLayout(HStackLayout(spacing: 12))
                : AnyLayout(VStackLayout(spacing: 10))
            layout {
                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Recording \(recorder.recordingLabel)")
                }

                Text(since, style: .timer)
                    .font(compact ? .body.monospacedDigit() : .title2.monospacedDigit())
                    .foregroundStyle(compact ? .secondary : .primary)

                Button("Stop Recording") {
                    Task { await recorder.stop() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        case .finishing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Saving recording…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var recorderMessages: some View {
        if let warning = recorder.silenceWarning {
            Text(warning)
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if let error = recorder.error {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }

        if recorder.unsavedRecording != nil {
            Button("Choose Folder and Save Recording…") {
                recorder.chooseFolderAndSave()
            }
            .controlSize(.small)
        }
    }

    private func addRecording(_ url: URL) {
        _ = addDroppedFiles([url])
        startQueue()
    }

    // Same path as a drop; the panel offers only the extensions a drop accepts.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        _ = addDroppedFiles(panel.urls)
    }

    // Status, not controls: language and destination read quietly here, and
    // the secondary controls live in Options.
    private var footer: some View {
        HStack(spacing: 16) {
            Text("New items: \(selectedLanguage.title)")
                .help("Language given to newly added and recorded items")

            Spacer()

            destinationStatus

            Spacer()

            optionsMenu
                .disabled(!recorder.isIdle)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var destinationStatus: some View {
        HStack(spacing: 6) {
            switch queue.destination.status {
            case .none:
                Button("Choose an output folder…") {
                    queue.destination.choose()
                }
                .buttonStyle(.link)
                .disabled(queue.isProcessing)
            case .ready(let url):
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Text("Saves to \(url.lastPathComponent)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.plain)
                .help("Show \(url.path(percentEncoded: false)) in Finder")
            case .unavailable(let message):
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Choose…") {
                    queue.destination.choose()
                }
                .buttonStyle(.link)
                .disabled(queue.isProcessing)
            }
        }
    }

    // Queue-level language: new items inherit it (it is the persisted default).
    // Existing jobs change only through Apply to all, and only while Waiting.
    private var optionsMenu: some View {
        Menu("Options") {
            Picker("Language", selection: $selectedLanguage) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }

            if queue.waitingCount >= 2 {
                Button("Apply Language to All Waiting") {
                    queue.applyLocale(selectedLanguage.locale)
                }
            }

            Divider()

            Button("Change Output Folder…") {
                queue.destination.choose()
            }
            .disabled(queue.isProcessing)

            if queue.hasYouTubeJobs {
                Toggle("Save YouTube Links as Source Packages", isOn: $savesSourcePackages)
                    .disabled(queue.isProcessing)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // No destination yet: ask once; cancelling starts nothing.
    private func startQueue() {
        guard queue.destination.isReady || queue.destination.choose() else { return }
        queue.start()
    }

    // Shown once any job has finished: counts and totals, one quiet line.
    @ViewBuilder
    private var summaryView: some View {
        let summary = queue.summary
        if summary.hasFinishedJobs {
            Text(summaryText(for: summary))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private func summaryText(for summary: BatchSummary) -> String {
        var parts = ["\(summary.succeeded) succeeded"]
        if summary.failed > 0 {
            parts.append("\(summary.failed) failed")
        }
        if let media = MetricsFormat.mediaDuration(summary.mediaDuration) {
            parts.append("\(media) of media")
            parts.append("processed in \(MetricsFormat.processingDuration(summary.processingDuration))")
        }
        if let speed = MetricsFormat.realtimeSpeed(
            mediaDuration: summary.mediaDuration,
            processingDuration: summary.processingDuration
        ) {
            parts.append("\(speed) realtime")
        }
        return parts.joined(separator: " · ")
    }

    private func addDroppedFiles(_ urls: [URL]) -> Bool {
        var sources: [JobSource] = []
        var hasUnsupportedItem = false
        for url in urls {
            if url.isFileURL {
                if supportedExtensions.contains(url.pathExtension.lowercased()) {
                    sources.append(.file(url))
                }
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                sources.append(linkSource(for: url))
            } else {
                hasUnsupportedItem = true
            }
        }

        guard !sources.isEmpty else {
            if hasUnsupportedItem {
                notice = "Drop a supported media file or a YouTube link."
            }
            return false
        }

        notice = nil
        for job in queue.enqueue(sources, locale: selectedLanguage.locale) {
            if case .file(let url) = job.source {
                Task {
                    job.mediaInfo = await loadMediaInfo(for: url)
                }
            }
        }
        return true
    }

    // Anything that is not a supported YouTube link becomes a Failed job.
    private func linkSource(for url: URL) -> JobSource {
        if let video = YouTubeURL.parse(url) {
            return .youtube(videoID: video.videoID, url: video.canonical)
        }
        return .invalid(input: url.absoluteString, reason: "Only YouTube links are supported.")
    }

    private func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        if urls.isEmpty, let text = pasteboard.string(forType: .string) {
            urls = text.split(whereSeparator: \.isWhitespace)
                .compactMap { URL(string: String($0)) }
                .filter { ["http", "https"].contains($0.scheme?.lowercased()) }
        }
        guard !urls.isEmpty else {
            notice = "Nothing to paste. Copy a YouTube link or a media file first."
            return
        }
        _ = addDroppedFiles(urls)
    }

    private func loadMediaInfo(for url: URL) async -> MediaInfo {
        let asset = AVURLAsset(url: url)

        let duration: CMTime

        do {
            duration = try await asset.load(.duration)
        } catch {
            duration = .zero
        }

        let seconds = max(0, CMTimeGetSeconds(duration))

        let resourceValues = try? url.resourceValues(
            forKeys: [.fileSizeKey]
        )

        let bytes = resourceValues?.fileSize ?? 0

        return MediaInfo(
            type: url.pathExtension.uppercased(),
            duration: formatDuration(seconds),
            fileSize: ByteCountFormatter.string(
                fromByteCount: Int64(bytes),
                countStyle: .file
            )
        )
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite else {
            return "Unknown duration"
        }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(
                format: "%d:%02d:%02d",
                hours,
                minutes,
                seconds
            )
        }

        return String(
            format: "%d:%02d",
            minutes,
            seconds
        )
    }

    private func saveTranscript(_ transcript: Transcript, for job: TranscriptionJob) {
        let panel = NSSavePanel()
        guard let markdownType = UTType(filenameExtension: "md") else {
            notice = "Markdown files are not supported on this Mac."
            return
        }

        panel.allowedContentTypes = [markdownType]
        panel.nameFieldStringValue = "\(transcript.sourceURL.deletingPathExtension().lastPathComponent).md"

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            try TranscriptMarkdownRenderer.render(transcript).write(
                to: destination,
                atomically: true,
                encoding: .utf8
            )
            job.savedTranscriptURL = destination
            notice = nil
        } catch {
            job.savedTranscriptURL = nil
            notice = error.localizedDescription
        }
    }
}

private struct JobRow: View {
    let job: TranscriptionJob
    let onSave: () -> Void
    let onRemove: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    nameView

                    if let metadata = job.metadata {
                        Text(metadata.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    } else if let mediaInfo = job.mediaInfo {
                        Text("\(mediaInfo.type) · \(mediaInfo.duration) · \(mediaInfo.fileSize)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }

                statusText
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                if case .complete = job.state, job.savedTranscriptURL == nil, let saveError = job.saveError {
                    Text("Not saved: \(saveError)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if case .complete = job.state, let savedTranscriptURL = job.savedTranscriptURL {
                    HStack(spacing: 0) {
                        Text("Saved · ")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button(savedTranscriptURL.lastPathComponent) {
                            NSWorkspace.shared.activateFileViewerSelecting([savedTranscriptURL])
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Language", selection: language) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .disabled(!job.isWaiting)

            if case .complete = job.state, job.saveError != nil, job.savedTranscriptURL == nil {
                Button("Save Transcript…", action: onSave)
                    .controlSize(.small)
            }

            if job.canRetry {
                Button("Retry", action: onRetry)
                    .controlSize(.small)
            }

            if job.isWaiting {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
                .accessibilityLabel("Remove from queue")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // Local files reveal in Finder; YouTube jobs open the video; a rejected link is plain text.
    @ViewBuilder
    private var nameView: some View {
        switch job.source {
        case .file(let url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                nameLabel(foreground: .tint)
            }
            .buttonStyle(.plain)
            .help("Reveal original file in Finder")
        case .youtube(_, let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                nameLabel(foreground: .tint)
            }
            .buttonStyle(.plain)
            .help("Open on YouTube")
        case .invalid:
            nameLabel(foreground: .secondary)
                .textSelection(.enabled)
        }
    }

    private func nameLabel(foreground: some ShapeStyle) -> some View {
        Text(job.displayName)
            .font(.callout.weight(.medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch job.state {
        case .waiting:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .downloading, .transcribing:
            ProgressView()
                .controlSize(.small)
        case .complete:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var statusText: some View {
        switch job.state {
        case .waiting:
            Text("Waiting")
                .foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading…")
                .foregroundStyle(.secondary)
        case .transcribing(let phase):
            Text(phase?.label ?? "Transcribing…")
                .foregroundStyle(.secondary)
        case .complete(let transcript, let processingDuration):
            Text("Complete · \(transcript.characterCount) characters · \(completionMetrics(for: transcript, processingDuration: processingDuration))")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text("Failed · \(message)")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    // The job owns a Locale; the picker only edits it while the job is Waiting.
    private var language: Binding<TranscriptionLanguage> {
        Binding(
            get: { TranscriptionLanguage.allCases.first { $0.locale == job.locale } ?? .english },
            set: { job.locale = $0.locale }
        )
    }

    private func completionMetrics(for transcript: Transcript, processingDuration: Duration) -> String {
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

// Shared by the per-job line and the queue summary so both always agree.
private enum MetricsFormat {
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

private struct WaveformBars: View {
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barHeights: [CGFloat] = [14, 23, 34, 46, 35, 24, 14]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !isAnimating || reduceMotion)) { timeline in
            HStack(alignment: .center, spacing: 5) {
                ForEach(barHeights.indices, id: \.self) { index in
                    Capsule()
                        .fill(.primary)
                        .frame(width: 5, height: barHeights[index])
                        .scaleEffect(
                            y: barScale(at: index, time: timeline.date.timeIntervalSinceReferenceDate),
                            anchor: .center
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 68, height: 52)
        .accessibilityHidden(true)
    }

    private func barScale(at index: Int, time: TimeInterval) -> CGFloat {
        guard isAnimating, !reduceMotion else { return 1 }

        let wave = (sin(time * 1.2 + Double(index) * 1.15) + 1) / 2
        return 0.45 + 0.55 * CGFloat(wave)
    }
}

private enum TranscriptionLanguage: String, CaseIterable, Identifiable {
    case english = "en-US"
    case dutch = "nl-NL"
    case german = "de-DE"
    case french = "fr-FR"
    case russian = "ru-RU"
    case spanish = "es-ES"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case turkish = "tr-TR"
    case swedish = "sv-SE"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    var title: String {
        switch self {
        case .english: "English"
        case .dutch: "Dutch"
        case .german: "German"
        case .french: "French"
        case .russian: "Russian"
        case .spanish: "Spanish"
        case .italian: "Italian"
        case .portuguese: "Portuguese"
        case .turkish: "Turkish"
        case .swedish: "Swedish"
        }
    }
}

import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var pasteLinks: (() -> Void)?
    @Entry var refreshTranscripts: (() -> Void)?
    @Entry var libraryCommands: LibraryCommands?
}

// A question the library asks before it acts, or a failure it reports.
private enum LibraryPrompt {
    case rename(LibraryTranscript)
    case newFolder(moving: LibraryTranscript?)
    case trash(LibraryTranscript)
    case failure(String)
}

struct ContentView: View {
    // Shared by all windows and Settings; owned by the app.
    let destination: OutputDestination
    @State private var queue: BatchQueue
    @State private var recorder = Recorder()
    @State private var isTargeted = false
    @State private var isQueueTargeted = false
    @FocusState private var isImportZoneFocused: Bool
    @AppStorage("defaultLanguage") private var selectedLanguage = TranscriptionLanguage.english
    @State private var notice: String?
    @State private var library = LibraryStore()
    @State private var selection: SidebarSelection? = .newTranscription
    // Bumped when the List deselects the selected row, so it draws the selection again.
    @State private var sidebarRefresh = 0
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    // A finished single job whose transcript should open as soon as the library lists it.
    @State private var pendingOpen: PendingOpen?
    // Jobs whose save has already been looked at, so each save is considered once.
    @State private var announcedSaves: Set<UUID> = []
    // The New Transcription workspace shows the retained queue from this batch on
    // (settled jobs of earlier batches are hidden, never deleted).
    @State private var firstVisibleBatch = 0
    // The window's only audio player (see AudioReviewPlayer).
    @State private var player = AudioReviewPlayer()
    @State private var prompt: LibraryPrompt?
    @State private var promptText = ""

    init(destination: OutputDestination) {
        self.destination = destination
        _queue = State(initialValue: BatchQueue(destination: destination))
    }

    private let supportedExtensions = [
        "mp4",
        "mov",
        "m4a",
        "mp3",
        "wav"
    ]

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            WorkspaceSidebar(
                jobs: inProgressJobs,
                library: library,
                destination: destination.status,
                selection: sidebarSelection,
                onRefresh: { refreshLibrary() },
                onRequest: handle
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 340)
        } detail: {
            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
            .frame(minWidth: 640, minHeight: 368)
        }
        // The paper continues under the title bar.
        .containerBackground(Theme.paper, for: .window)
        .contentShape(Rectangle())
        .dropDestination(for: URL.self) { urls, _ in
            addDroppedFiles(urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .focusedSceneValue(\.pasteLinks, pasteFromClipboard)
        .focusedSceneValue(\.refreshTranscripts) { refreshLibrary() }
        .focusedSceneValue(\.libraryCommands, LibraryCommands(
            selected: selectedTranscript, canCreateFolder: destination.isReady, request: handle))
        .modifier(LibraryPromptModifier(
            prompt: $prompt, text: $promptText, library: library, commit: commit))
        // Another window changed files: look again.
        .onReceive(NotificationCenter.default.publisher(for: .libraryDidChange)) { note in
            if (note.object as? LibraryStore) !== library { refreshLibrary(recheckFolder: false) }
        }
        .onAppear {
            // Makes this window's work count in the app-wide guards (Settings, folder).
            destination.register(queue, recorder)
            recorder.refreshApps()
            library.refresh(folder: destination.readyFolder)
        }
        // Closing the window must not leave a recording running unseen.
        .onDisappear {
            recorder.cancel()
            player.stop()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            recorder.refreshApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            recorder.refreshApps()
        }
        // The library follows the output folder, a saved job, and the app coming
        // back to the front (files may have changed meanwhile).
        .onChange(of: destination.readyFolder) { _, folder in
            library.refresh(folder: folder)
        }
        .onChange(of: folderBlocked) { _, blocked in
            if !blocked && notice == Self.folderBlockedNotice { notice = nil }
        }
        .onChange(of: queue.currentBatch) { _, batch in
            firstVisibleBatch = QueueWorkspace.firstVisibleBatch(forNewBatch: batch)
        }
        .onChange(of: savedJobCount) { noteSavedJobs() }
        // The scan that follows a save answers the pending open.
        .onChange(of: library.revision) { resolvePendingOpen() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLibrary()
        }
        // A selection that no longer exists (job joined to its library entry, item
        // removed outside the app, folder changed) goes back to New Transcription.
        .onChange(of: library.items) { selectionStillExists() }
        // Audio belongs to the open transcript only: any other selection silences it.
        .onChange(of: selection) { _, new in
            if case .transcript(let id) = new, player.itemID == id { return }
            player.stop()
        }
        .onChange(of: inProgressJobs.map(\.id)) { selectionStillExists() }
    }

    // The live jobs, failed jobs and Complete jobs whose save failed. A job that
    // was saved into the listed output folder is shown once, as a library item.
    private var inProgressJobs: [TranscriptionJob] {
        queue.jobs.filter { job in
            guard case .complete = job.state else { return true }
            guard let url = job.savedTranscriptURL else { return true }
            return LibraryJoin.isAwaitingEntry(
                savedURL: url, folder: library.folder, in: library.joinIndex, seen: library.seenPaths)
        }
    }

    private var savedJobCount: Int {
        queue.jobs.count { $0.savedTranscriptURL != nil }
    }

    private func refreshLibrary(recheckFolder: Bool = true) {
        // Re-resolves the folder so one that went away shows its unavailable status.
        // Not while any window's queue or recording uses the shared folder.
        if recheckFolder && destination.canChangeFolder { destination.refresh() }
        library.refresh(folder: destination.readyFolder)
    }

    private var selectedTranscript: LibraryTranscript? {
        if case .transcript(let id) = selection { library.items.first { $0.id == id } } else { nil }
    }

    // MARK: library actions

    private func handle(_ request: LibraryRequest) {
        switch request {
        case .rename(let item):
            promptText = item.title
            prompt = .rename(item)
        case .newFolder(let moving):
            promptText = ""
            prompt = .newFolder(moving: moving)
        case .trash(let item):
            prompt = .trash(item)
        case .togglePin(let item):
            attempt { try library.setPinned(item, !item.isPinned) }
        case .toggleArchive(let item):
            attempt { try library.setArchived(item, !item.isArchived) }
        case .move(let item, let folder):
            attempt { follow(item, to: try library.move(item, to: folder)) }
        }
    }

    private func commit(_ prompt: LibraryPrompt) {
        attempt {
            switch prompt {
            case .rename(let item):
                follow(item, to: try library.rename(item, to: promptText))
            case .newFolder(let moving):
                let folder = try library.createFolder(named: promptText)
                if let moving { follow(moving, to: try library.move(moving, to: folder)) }
            case .trash(let item):
                try library.trash(item)
                if player.itemID == item.id { player.stop() }
                if case .transcript(item.id) = selection { showNewTranscription() }
            case .failure:
                break
            }
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { prompt = .failure(error.localizedDescription) }
    }

    // A renamed or moved transcript keeps its place in the sidebar and in the
    // queue; its audio stops, because the file it was playing has moved.
    private func follow(_ old: LibraryTranscript, to new: LibraryTranscript) {
        queue.relocate(from: old.markdownURL, to: new.markdownURL)
        guard case .transcript(old.id) = selection else { return }
        if player.itemID == old.id { player.stop() }
        selection = .transcript(new.id)
    }

    private var isReviewingTranscript: Bool {
        if case .transcript = selection { true } else { false }
    }

    // A saved job asks to open its transcript when it is the whole batch and the
    // user is not reading another transcript. The request names the URL the save
    // reported and waits for a scan that started after the save.
    private func noteSavedJobs() {
        let fresh = queue.jobs.filter { $0.savedTranscriptURL != nil && !announcedSaves.contains($0.id) }
        announcedSaves.formUnion(fresh.map(\.id))
        if fresh.count == 1, let job = fresh.first, let url = job.savedTranscriptURL,
           AutoOpen.shouldRequest(
               batchJobCount: queue.jobs.count { $0.batch == job.batch },
               userIsReviewingTranscript: isReviewingTranscript) {
            pendingOpen = PendingOpen(savedURL: url)
        }
        refreshLibrary(recheckFolder: false)
    }

    private func resolvePendingOpen() {
        guard let pending = pendingOpen else { return }
        pendingOpen = nil
        if case .open(let item) = pending.resolve(in: library.joinIndex, userIsReviewingTranscript: isReviewingTranscript) {
            selection = .transcript(item.id)
        }
    }

    private func isSettled(_ job: TranscriptionJob) -> Bool {
        if case .complete = job.state { job.savedTranscriptURL != nil } else { false }
    }

    private var queueEntries: [QueueEntry] {
        queue.jobs.map {
            QueueEntry(id: $0.id, batch: $0.batch, isSettled: isSettled($0), isUnfinished: $0.isUnfinished)
        }
    }

    // What the New Transcription workspace shows: a window over the retained queue.
    private var visibleJobs: [TranscriptionJob] {
        let shown = Set(QueueWorkspace.visible(queueEntries, firstVisibleBatch: firstVisibleBatch))
        return queue.jobs.filter { shown.contains($0.id) }
    }

    // Leaving a transcript for New Transcription starts a fresh workspace: finished
    // batches are put behind the user (still in the queue, still in the library);
    // a batch that is still running stays whole.
    private func showNewTranscription() {
        if isReviewingTranscript {
            firstVisibleBatch = QueueWorkspace.firstVisibleBatch(afterStartingFresh: queueEntries)
        }
        selection = .newTranscription
    }

    // The sidebar's own selection goes through the same rule; moves made by the
    // app (an automatic open, a vanished item) do not.
    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: { _ = sidebarRefresh; return selection },
            set: { newValue in
                // A Command-click on the selected row asks the List to deselect it: there is always a selection.
                // The selection did not change, so the List is told to show it again.
                guard let chosen = SidebarSelectionRule.next(current: selection, proposed: newValue) else { return }
                if newValue == nil { sidebarRefresh += 1 }
                if chosen == .newTranscription { showNewTranscription() } else { selection = chosen }
            })
    }

    private func jobRow(_ job: TranscriptionJob) -> some View {
        let entry = job.savedTranscriptURL.flatMap { LibraryJoin.item(forSavedURL: $0, in: library.joinIndex) }
        let awaiting = job.savedTranscriptURL.map {
            LibraryJoin.isAwaitingEntry(
                savedURL: $0, folder: library.folder, in: library.joinIndex, seen: library.seenPaths)
        } ?? false
        return JobRow(
            job: job,
            onOpen: entry.map { item in { selection = .transcript(item.id) } },
            savedElsewhere: job.savedTranscriptURL != nil && entry == nil && !awaiting,
            onSave: {
                if case .complete(let transcript, _) = job.state {
                    saveTranscript(transcript, for: job)
                }
            }, onCopy: {
                copyMarkdown(for: job)
            }, onRemove: {
                queue.remove(job)
            }, onRetry: {
                queue.retry(job)
                startQueue()
            })
    }

    private var queueRows: some View {
        let jobs = visibleJobs
        return VStack(spacing: 0) {
            ForEach(jobs) { job in
                if job.id != jobs.first?.id {
                    Theme.rule.frame(height: 1).accessibilityHidden(true)
                }
                jobRow(job)
            }
        }
    }

    private func selectionStillExists() {
        switch selection {
        case .job(let id) where !inProgressJobs.contains { $0.id == id }:
            selection = .newTranscription
        case .transcript(let id) where !library.items.contains { $0.id == id }:
            selection = .newTranscription
        default:
            break
        }
    }

    // New Transcription and a live job show the queue; a transcript opens inline.
    @ViewBuilder
    private var detail: some View {
        if case .transcript(let id) = selection, let item = library.items.first(where: { $0.id == id }) {
            TranscriptReviewView(item: item, player: player)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if visibleJobs.isEmpty {
            // Mark and tagline above one surface with two inputs: import on the
            // left, record on the right. Centered, so a taller window does not
            // leave a loose empty lower third.
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    BrandMark()
                    BrandLine()
                }

                HStack(spacing: 0) {
                    importZone
                    Theme.rule.frame(width: 1).accessibilityHidden(true)
                    recordZone
                        .frame(width: 260)
                        .frame(maxHeight: .infinity)
                        .background(Theme.raised)
                }
                .fixedSize(horizontal: false, vertical: true)
                .surface()

                if hasMessages {
                    messages(alignment: .center)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 560, maxHeight: .infinity)
            .padding(40)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                actionBar

                if hasMessages {
                    messages(alignment: .leading)
                        .padding(.horizontal, 4)
                }

                // Clear belongs to the queue, so it heads the queue with the summary.
                // It stays visible while a job runs, disabled, so the header never jumps.
                HStack(spacing: 10) {
                    summaryView
                    Spacer(minLength: 8)
                    // Existing jobs change language only through this, and only while
                    // Waiting. Left of Clear Queue, so Clear Queue never moves.
                    if queue.waitingCount >= 2 {
                        Button("Apply Language to All Waiting") {
                            queue.applyLocale(selectedLanguage.locale)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!destination.canChangeLanguage)
                        .help("Give every waiting item the default language, \(selectedLanguage.title).")
                    }
                    Button("Clear Queue") {
                        queue.clear()
                        notice = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!queue.canClear)
                    .help("Remove all items from the queue. Saved transcripts and media stay in place.")
                }
                .padding(.horizontal, 4)
                .frame(minHeight: 24)

                ScrollView {
                    queueRows
                }
                .background(Theme.raised)
                .surface()
                .overlay {
                    if isTargeted || isQueueTargeted {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1.5)
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
            .frame(maxWidth: 720, maxHeight: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    private var hasMessages: Bool {
        recorder.silenceWarning != nil || recorder.error != nil || recorder.unsavedRecording != nil || notice != nil
    }

    // Recorder messages and the notice read as one group below the inputs.
    private func messages(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            recorderMessages

            if let notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // The drop target is also the file picker.
    private var importZone: some View {
        Button(action: chooseFiles) {
            VStack(spacing: 6) {
                Text(isTargeted ? "Drop to add" : "Drop media")
                    .font(.headline)
                Text("or click to choose files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⌘V pastes a YouTube link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Theme.recessed))
            .contentShape(Rectangle())
        }
        // The system ring is drawn on the button's rectangle and would stick out
        // past the surface's rounded corners, so the zone draws it on its own shape.
        .focusEffectDisabled()
        .focused($isImportZoneFocused)
        .overlay {
            if isImportZoneFocused {
                UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .disabled(!recorder.isIdle)
        .accessibilityLabel("Choose files")
        .accessibilityHint("Or drop media, or press Command V to paste a YouTube link")
    }

    // Record is one more input: the finished recording is saved to the output
    // folder and then queued exactly like a dropped file. The choice is made
    // inline; nothing is captured or requested before Record.
    @ViewBuilder
    private var recordZone: some View {
        Group {
            if recorder.isIdle {
                VStack(spacing: 10) {
                    Text("Record audio")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    appPicker(maxWidth: 200)
                    micToggle
                    recordButton
                        .controlSize(.large)
                        .padding(.top, 2)
                }
                .accessibilityElement(children: .contain)
            } else {
                recordingStatus(compact: false)
            }
        }
        .padding(16)
        // The idle controls' height, so the surface keeps its size while
        // starting, recording and saving.
        .frame(minHeight: 148)
    }

    private func appPicker(maxWidth: CGFloat) -> some View {
        Picker("App audio", selection: $recorder.selectedAppID) {
            Text("No app audio").tag(String?.none)
            Divider()
            ForEach(recorder.apps) { app in
                Text(app.name).tag(String?.some(app.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: maxWidth)
        // The full name of a selected app, which the picker may truncate.
        .help(recorder.apps.first { $0.id == recorder.selectedAppID }?.name ?? "")
    }

    private var micToggle: some View {
        Toggle("Mic", isOn: $recorder.includesMicrophone)
            .toggleStyle(.checkbox)
            .tint(Theme.wineFill)
            .fixedSize()
            .accessibilityLabel("Include microphone")
    }

    // No ready folder while running work uses it: choose() refuses its panel,
    // so Record or Transcribe would silently do nothing. The footer says why.
    private var folderBlocked: Bool { !destination.isReady && !destination.canChangeFolder }
    private static let folderBlockedNotice = "The output folder is unavailable. Choose another one when the running work finishes."

    private var recordButton: some View {
        Button("Record", action: startRecording)
            .disabled(!recorder.canRecord || folderBlocked)
    }

    @ViewBuilder
    private var transcribeButton: some View {
        if recorder.isIdle && !queue.isProcessing && queue.waitingCount > 0 {
            Button("Transcribe \(queue.waitingCount)", action: startQueue)
                .buttonStyle(.borderedProminent)
                .tint(Theme.wineFill)
                .disabled(folderBlocked)
        }
    }

    // Inputs on the left (recessed), recording and Transcribe on the right
    // (raised). A running recording replaces the record segment. When one row
    // does not fit, the bar falls back to two rows.
    private var actionBar: some View {
        Group {
            if recorder.isIdle {
                ViewThatFits(in: .horizontal) {
                    actionBarOneRow
                    actionBarTwoRows
                }
            } else {
                HStack(spacing: 0) {
                    addFilesSegment
                    Theme.rule.frame(width: 1).accessibilityHidden(true)
                    recordingStatus(compact: true)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .background(Theme.raised)
                        .overlay(Color.red.opacity(0.07).allowsHitTesting(false).accessibilityHidden(true))
                }
                .frame(height: 44)
            }
        }
        .surface()
        .controlSize(.large)
    }

    private var addFilesSegment: some View {
        Button("Add Files", action: chooseFiles)
            .disabled(!recorder.isIdle)
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .background(Theme.recessed)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var actionBarOneRow: some View {
        HStack(spacing: 0) {
            addFilesSegment
            Theme.rule.frame(width: 1).accessibilityHidden(true)
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    appPicker(maxWidth: 150)
                    micToggle
                    recordButton
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Record audio")

                transcribeButton
            }
            .padding(.horizontal, 12)
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(Theme.raised)
        }
        .frame(height: 44)
    }

    private var actionBarTwoRows: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Add Files", action: chooseFiles)
                Spacer()
                Text("⌘V pastes a YouTube link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.recessed)

            Theme.rule.frame(height: 1).accessibilityHidden(true)

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    appPicker(maxWidth: 260)
                    micToggle
                    Spacer(minLength: 8)
                    recordButton
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Record audio")

                transcribeButton
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Theme.raised)
        }
    }

    // Starts from the visible selection; the app list is kept current by the
    // launch and termination notifications.
    private func startRecording() {
        Task {
            await recorder.record(to: destination) { addRecording($0, startedAt: $1) }
            // record() refreshes the folder first. If it vanished while a
            // transcription or recording runs, choose() refuses its panel and nothing starts.
            if recorder.isIdle && recorder.error == nil && folderBlocked {
                notice = Self.folderBlockedNotice
            }
        }
    }

    // Stacked in the record zone when the list is empty, one row in the action bar otherwise.
    @ViewBuilder
    private func recordingStatus(compact: Bool) -> some View {
        switch recorder.state {
        case .idle:
            EmptyView()
        case .starting:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting…")
                    .foregroundStyle(.secondary)
            }
        case .recording(let since):
            if compact {
                HStack(spacing: 10) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Recording · \(recorder.recordingLabel)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(since, style: .timer)
                        .font(.title3.monospacedDigit())
                    stopButton
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Recording")
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red)
                            .accessibilityHidden(true)
                        Text("Recording")
                            .font(.headline)
                    }
                    Text(recorder.recordingLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(since, style: .timer)
                        .font(.title2.monospacedDigit())
                    stopButton
                        .controlSize(.large)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Recording")
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

    private var stopButton: some View {
        Button("Stop Recording") {
            Task { await recorder.stop() }
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
            .disabled(!destination.canChangeFolder)
        }
    }

    // The recording was saved as an entry folder holding its audio; the transcript
    // is written into that same folder.
    private func addRecording(_ url: URL, startedAt: Date) {
        _ = addDroppedFiles([url], recording: (url.deletingLastPathComponent(), startedAt))
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
    // preferences live in Settings.
    private var footer: some View {
        HStack(spacing: 16) {
            Text("New items: \(selectedLanguage.title)")
                .help("Language given to newly added and recorded items")

            Spacer()

            destinationStatus

            Spacer()

            // Opens the same window as Settings… in the app menu and ⌘,. Never
            // disabled: the controls inside lock themselves while work runs.
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var destinationStatus: some View {
        HStack(spacing: 6) {
            switch destination.status {
            case .none:
                Button("Choose an output folder…") {
                    destination.choose()
                }
                .buttonStyle(.link)
                .disabled(!destination.canChangeFolder)
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
                    destination.choose()
                }
                .buttonStyle(.link)
                .disabled(!destination.canChangeFolder)
            }
        }
    }

    // No destination yet: ask once; cancelling starts nothing.
    private func startQueue() {
        guard destination.isReady || destination.choose() else { return }
        queue.start()
    }

    // Shown once any job has finished: counts and totals, one quiet line.
    @ViewBuilder
    private var summaryView: some View {
        let summary = queue.summary(of: visibleJobs)
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

    private func addDroppedFiles(_ urls: [URL], recording: (folder: URL, startedAt: Date)? = nil) -> Bool {
        // Input and its notices live in the queue view.
        showNewTranscription()
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
                notice = "Not supported. Drop an MP4, MOV, M4A, MP3 or WAV file, or a YouTube link."
            }
            return false
        }

        notice = nil
        for job in queue.enqueue(sources, locale: selectedLanguage.locale) {
            job.recording = recording
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
        showNewTranscription()
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

    // Read-only: puts the job's Markdown on the pasteboard. The result tells
    // the row whether it may show "Copied".
    private static let copyFailedNotice = "Could not copy the transcript to the clipboard."

    private func copyMarkdown(for job: TranscriptionJob) -> Bool {
        guard case .complete(let transcript, _) = job.state else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(job.markdown(for: transcript), forType: .string) else {
            notice = Self.copyFailedNotice
            return false
        }
        // A success clears only this action's own earlier error, never another notice.
        if notice == Self.copyFailedNotice { notice = nil }
        return true
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
            try job.markdown(for: transcript).write(
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
    // Present when the job's transcript is listed in the library.
    let onOpen: (() -> Void)?
    // Saved, but not into the folder the library is listing.
    let savedElsewhere: Bool
    let onSave: () -> Void
    // Returns whether the pasteboard accepted the text.
    let onCopy: () -> Bool
    let onRemove: () -> Void
    let onRetry: () -> Void

    // Confirmation lives only in this row. Every click bumps `copyClicks`,
    // which restarts the reset task; the task is cancelled with the row.
    @State private var copied = false
    @State private var copyClicks = 0

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    nameView

                    if let metadata = job.metadata {
                        Text(metadata.detailText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    } else if let mediaInfo = job.mediaInfo {
                        Text("\(mediaInfo.type) · \(mediaInfo.duration) · \(mediaInfo.fileSize)")
                            .font(.caption.monospacedDigit())
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

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([savedTranscriptURL])
                        } label: {
                            Text(savedTranscriptURL.lastPathComponent)
                                .font(.caption.monospaced())
                                .underline(true, color: Theme.emphasis.opacity(0.55))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.plain)
                        .pointerStyle(.link)
                        .help("Show in Finder")
                    }
                }

                if savedElsewhere {
                    Text("Not in the current library: saved to another output folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // The transcript is saved; only its timing file is not.
                if case .complete = job.state, let sidecarWarning = job.sidecarWarning {
                    Text(sidecarWarning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // The language can only change while the job waits; afterwards it is shown as text.
            if job.isWaiting {
                Picker("Language", selection: language) {
                    ForEach(TranscriptionLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            } else {
                Text(language.wrappedValue.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let onOpen {
                Button("Open", action: onOpen)
                    .controlSize(.small)
                    .help("Open this transcript")
                    .accessibilityLabel("Open transcript")
            }

            if case .complete = job.state {
                Button {
                    copied = onCopy()
                    copyClicks += 1
                } label: {
                    // The hidden "Copied" reserves its width so the row does not shift.
                    ZStack {
                        Text("Copied").hidden()
                        Text(copied ? "Copied" : "Copy")
                    }
                }
                .controlSize(.small)
                .help("Copy transcript as Markdown")
                .accessibilityLabel("Copy transcript as Markdown")
                .accessibilityValue(copied ? "Copied" : "")
                .task(id: copyClicks) {
                    guard copied else { return }
                    try? await Task.sleep(for: .milliseconds(1500))
                    if !Task.isCancelled { copied = false }
                }
            }

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
                .accessibilityLabel("Remove from queue")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // Local files reveal in Finder; YouTube jobs open the video; a rejected link is plain text.
    @ViewBuilder
    private var nameView: some View {
        switch job.source {
        case .file(let url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                nameLabel(foreground: .primary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help("Reveal original file in Finder")
        case .youtube(_, let url):
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                nameLabel(foreground: .primary)
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
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

// The brand mark: the website's seven-bar geometry. Static and decorative.
private struct BrandMark: View {
    private let barHeights: [CGFloat] = [14, 26, 38, 52, 38, 26, 14]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(barHeights.indices, id: \.self) { index in
                Capsule()
                    .fill(.primary)
                    .frame(width: 6, height: barHeights[index])
            }
        }
        .frame(width: 66, height: 52)
        .accessibilityHidden(true)
    }
}

// "Media in. Markdown out." with the one serif italic word.
private struct BrandLine: View {
    var body: some View {
        Text("Media in. \(Text("Markdown").font(.custom("Georgia-Italic", size: 18)).foregroundStyle(Theme.emphasis)) out.")
            .font(.title3.bold())
            .tracking(-0.3)
    }
}

enum TranscriptionLanguage: String, CaseIterable, Identifiable {
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


// The alerts of the library actions: a name to type, a Trash confirmation, a failure.
private struct LibraryPromptModifier: ViewModifier {
    @Binding var prompt: LibraryPrompt?
    @Binding var text: String
    let library: LibraryStore
    let commit: (LibraryPrompt) -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                      presenting: prompt) { current in
            switch current {
            case .rename:
                TextField("Name", text: $text)
                Button("Rename") { commit(current) }
                Button("Cancel", role: .cancel) {}
            case .newFolder:
                TextField("Name", text: $text)
                Button("Create") { commit(current) }
                Button("Cancel", role: .cancel) {}
            case .trash:
                Button("Move to Trash", role: .destructive) { commit(current) }
                Button("Cancel", role: .cancel) {}
            case .failure:
                Button("OK", role: .cancel) {}
            }
        } message: { current in
            Text(message(for: current))
        }
    }

    private var title: String {
        switch prompt {
        case .rename: "Rename Transcript"
        case .newFolder(let moving): moving == nil ? "New Folder" : "New Folder and Move"
        case .trash(let item): "Move “\(item.title)” to the Trash?"
        case .failure: "Couldn’t Do That"
        case nil: ""
        }
    }

    private func message(for prompt: LibraryPrompt) -> String {
        switch prompt {
        case .rename: return "Renames the folder and its Markdown file. The transcript itself is not changed."
        case .newFolder: return "Creates a folder in the output folder."
        case .trash(let item):
            let files = LibraryOperations.contents(of: item).map {
                "\($0.name) (\(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)))"
            }
            return "The folder and everything in it moves to the Trash: \(files.joined(separator: ", ")). "
                + "Audio kept with the transcript goes with it. You can put it back from the Trash."
        case .failure(let reason): return reason
        }
    }
}

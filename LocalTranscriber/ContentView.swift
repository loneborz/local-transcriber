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
    case renameFolder(LibraryFolder)
    case trashFolder(LibraryFolder, entries: Int)
    // The folder holds files the app did not create, so it is not trashed from here.
    case folderNeedsReview(LibraryFolder, names: [String])
    case failure(title: String, reason: String)
}

struct ContentView: View {
    // Shared by all windows and Settings; owned by the app.
    let destination: OutputDestination
    // One queue for the whole app (see MyApp); every window shows and feeds it.
    let queue: BatchQueue
    // This window; the jobs it adds open their transcript here, not in other windows.
    @State private var windowID = UUID()
    @State private var recorder = Recorder()
    @State private var isTargeted = false
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
    // The window's only audio player (see AudioReviewPlayer).
    @State private var player = AudioReviewPlayer()
    @State private var prompt: LibraryPrompt?
    @State private var promptText = ""

    init(destination: OutputDestination, queue: BatchQueue) {
        self.destination = destination
        self.queue = queue
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
                queue: queue,
                jobs: inProgressJobs,
                processing: processingActions,
                recordingBanner: recorder.isIdle ? nil : AnyView(recordingStatus(compact: true)),
                library: library,
                destination: destination.status,
                selection: sidebarSelection,
                onNewTranscription: showNewTranscription,
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
        // The title bar says where the user is (see `contextTitle`).
        .navigationTitle(contextTitle)
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
        .modifier(LibraryPromptModifier(prompt: $prompt, text: $promptText, commit: commit))
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
            if let id = new?.transcriptID, player.itemID == id { return }
            player.stop()
        }
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
        selection?.transcriptID.flatMap { id in library.items.first { $0.id == id } }
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
            let verb = item.isPinned ? "unpin" : "pin"
            attempt("Couldn’t \(verb) “\(item.title)”") { try library.setPinned(item, !item.isPinned) }
        case .toggleArchive(let item):
            let verb = item.isArchived ? "unarchive" : "archive"
            attempt("Couldn’t \(verb) “\(item.title)”") { try library.setArchived(item, !item.isArchived) }
        case .move(let item, let folder):
            attempt("Couldn’t move “\(item.title)”") { follow(item, to: try library.move(item, to: folder)) }
        case .renameFolder(let folder):
            promptText = folder.name
            prompt = .renameFolder(folder)
        case .trashFolder(let folder):
            do {
                let contents = try LibraryOperations.inspect(folder)
                prompt = contents.isSafeToTrash
                    ? .trashFolder(folder, entries: contents.entryCount)
                    : .folderNeedsReview(folder, names: contents.unmanaged)
            } catch {
                prompt = .failure(title: "Couldn’t check the folder “\(folder.name)”", reason: error.localizedDescription)
            }
        }
    }

    private func commit(_ prompt: LibraryPrompt) {
        switch prompt {
        case .rename(let item):
            attempt("Couldn’t rename “\(item.title)”") { follow(item, to: try library.rename(item, to: promptText)) }
        case .newFolder(let moving):
            attempt("Couldn’t create the folder") {
                let folder = try library.createFolder(named: promptText)
                if let moving { follow(moving, to: try library.move(moving, to: folder)) }
            }
        case .trash(let item):
            attempt("Couldn’t move “\(item.title)” to the Trash") {
                try library.trash(item)
                if player.itemID == item.id { player.stop() }
                if selection?.transcriptID == item.id { showNewTranscription() }
            }
        case .renameFolder(let folder):
            attempt("Couldn’t rename the folder “\(folder.name)”") {
                let renamed = try library.renameFolder(folder, to: promptText)
                followFolder(folder, to: renamed)
            }
        case .trashFolder(let folder, _):
            attempt("Couldn’t move the folder “\(folder.name)” to the Trash") {
                let inside = selection?.transcriptID?.hasPrefix(folder.url.standardizedFileURL.path + "/") == true
                try library.trashFolder(folder)
                if inside { player.stop(); showNewTranscription() }
            }
        case .folderNeedsReview(let folder, _):
            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
        case .failure:
            break
        }
    }

    private func attempt(_ title: String, _ work: () throws -> Void) {
        do { try work() } catch { prompt = .failure(title: title, reason: error.localizedDescription) }
    }

    // A folder was renamed: an open transcript inside it follows to its new path.
    private func followFolder(_ old: LibraryFolder, to new: LibraryFolder) {
        let oldPath = old.url.standardizedFileURL.path
        for job in queue.jobs {
            if let url = job.savedTranscriptURL, url.standardizedFileURL.path.hasPrefix(oldPath + "/") {
                job.savedTranscriptURL = URL(fileURLWithPath: new.url.path + String(url.standardizedFileURL.path.dropFirst(oldPath.count)))
            }
        }
        guard let current = selection, let id = current.transcriptID, id.hasPrefix(oldPath + "/") else { return }
        if player.itemID == id { player.stop() }
        selection = current.replacingTranscript(with: new.url.standardizedFileURL.path + String(id.dropFirst(oldPath.count)))
    }

    // A renamed or moved transcript keeps its place in the sidebar and in the
    // queue; its audio stops, because the file it was playing has moved.
    private func follow(_ old: LibraryTranscript, to new: LibraryTranscript) {
        queue.relocate(from: old.markdownURL, to: new.markdownURL)
        guard let current = selection, current.transcriptID == old.id else { return }
        if player.itemID == old.id { player.stop() }
        selection = current.replacingTranscript(with: new.id)
    }

    private var isReviewingTranscript: Bool {
        selection?.transcriptID != nil
    }

    // A saved job asks to open its transcript when it is the whole batch and the
    // user is not reading another transcript. The request names the URL the save
    // reported and waits for a scan that started after the save.
    private func noteSavedJobs() {
        let fresh = queue.jobs.filter {
            $0.originWindow == windowID && $0.savedTranscriptURL != nil && !announcedSaves.contains($0.id)
        }
        announcedSaves.formUnion(fresh.map(\.id))
        if fresh.count == 1, let job = fresh.first, let url = job.savedTranscriptURL,
           AutoOpen.shouldRequest(
               batchJobCount: queue.batchSize(of: job),
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

    private func showNewTranscription() {
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

    // The native title bar says where the user is.
    private var contextTitle: String {
        switch selection {
        case .newTranscription, nil: return "New Transcription"
        case .pinned: return "Library / Pinned"
        case .transcript:
            guard let item = selectedTranscript else { return "Library" }
            if item.isArchived { return "Library / Archive" }
            return "Library / " + (item.group?.lastPathComponent ?? "Recent")
        }
    }

    private var processingActions: ProcessingActions {
        ProcessingActions(
            openTarget: { job in
                job.savedTranscriptURL
                    .flatMap { LibraryJoin.item(forSavedURL: $0, in: library.joinIndex) }
                    .map { item in { selection = .transcript(item.id) } }
            },
            savedElsewhere: { job in
                guard let url = job.savedTranscriptURL else { return false }
                let entry = LibraryJoin.item(forSavedURL: url, in: library.joinIndex)
                let awaiting = LibraryJoin.isAwaitingEntry(
                    savedURL: url, folder: library.folder, in: library.joinIndex, seen: library.seenPaths)
                return entry == nil && !awaiting
            },
            save: { job in
                if case .complete(let transcript, _) = job.state { saveTranscript(transcript, for: job) }
            },
            copy: { copyMarkdown(for: $0) },
            retry: { job in
                queue.retry(job)
                // No output folder chosen: the job goes back to waiting for its Start.
                if !startQueue(only: [job]) { job.isStarted = false }
            },
            remove: { queue.remove($0) },
            start: { startQueue() },
            applyLanguage: { queue.applyLocale(selectedLanguage.locale) },
            clearFinished: { queue.clearFinished(); notice = nil },
            canStart: !destination.isRecording && !folderBlocked,
            canChangeLanguage: destination.canChangeLanguage,
            defaultLanguageTitle: selectedLanguage.title
        )
    }

    private func selectionStillExists() {
        switch selection {
        case .pinned(let id), .transcript(let id):
            // Keep the highlight on a row that exists: a pinned entry that was unpinned
            // or archived leaves Pinned; a loose entry that was pinned leaves Recent.
            guard let item = library.items.first(where: { $0.id == id }) else {
                selection = .newTranscription
                return
            }
            let inPinned = item.isPinned && !item.isArchived
            let hasListRow = item.isArchived || item.group != nil || !item.isPinned
            if case .pinned = selection, !inPinned { selection = .transcript(id) }
            if case .transcript = selection, !hasListRow { selection = .pinned(id) }
        default:
            break
        }
    }

    // New Transcription and a live job show the queue; a transcript opens inline.
    @ViewBuilder
    private var detail: some View {
        if let id = selection?.transcriptID, let item = library.items.first(where: { $0.id == id }) {
            TranscriptReviewView(item: item, player: player)
        } else {
            content
        }
    }

    // New Transcription is an input surface: mark and tagline above one surface
    // with two inputs, import on the left and record on the right. The work itself
    // is listed in the sidebar's Processing section.
    private var content: some View {
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
        let before = Set(queue.jobs.map(\.id))
        _ = addDroppedFiles([url], recording: (url.deletingLastPathComponent(), startedAt))
        // Stop is the user's start for the recording; other waiting jobs are not started with it.
        startQueue(only: queue.jobs.filter { !before.contains($0.id) })
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
            languagePicker

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
        .controlSize(.small)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // The default language for newly added and recorded items (waiting items keep
    // theirs). Locked while a recording runs; same preference as before.
    private var languagePicker: some View {
        HStack(spacing: 6) {
            Text("New items:")
            Picker("Language for new items", selection: $selectedLanguage) {
                ForEach(TranscriptionLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!destination.canChangeLanguage)
        }
        .help(destination.canChangeLanguage
              ? "Language given to newly added and recorded items. Waiting items keep theirs unless you use Apply Language to All Waiting."
              : "The language can’t change while recording.")
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
    @discardableResult
    private func startQueue(only jobs: [TranscriptionJob]? = nil) -> Bool {
        guard destination.isReady || destination.choose() else { return false }
        queue.start(jobs)
        return true
    }

    private func addDroppedFiles(_ urls: [URL], recording: (folder: URL, startedAt: Date)? = nil) -> Bool {
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
                showNewTranscription()   // the notice lives on the input surface
            }
            return false
        }

        notice = nil
        for job in queue.enqueue(sources, locale: selectedLanguage.locale, originWindow: windowID) {
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
        let pasteboard = NSPasteboard.general
        var urls = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        if urls.isEmpty, let text = pasteboard.string(forType: .string) {
            urls = text.split(whereSeparator: \.isWhitespace)
                .compactMap { URL(string: String($0)) }
                .filter { ["http", "https"].contains($0.scheme?.lowercased()) }
        }
        guard !urls.isEmpty else {
            notice = "Nothing to paste. Copy a YouTube link or a media file first."
            showNewTranscription()
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
    let commit: (LibraryPrompt) -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                      presenting: prompt) { current in
            switch current {
            case .rename, .renameFolder:
                TextField("Name", text: $text)
                Button("Rename") { commit(current) }
                Button("Cancel", role: .cancel) {}
            case .newFolder:
                TextField("Name", text: $text)
                Button("Create") { commit(current) }
                Button("Cancel", role: .cancel) {}
            case .trash, .trashFolder:
                Button("Move to Trash", role: .destructive) { commit(current) }
                Button("Cancel", role: .cancel) {}
            case .folderNeedsReview:
                Button("Show in Finder") { commit(current) }
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
        case .renameFolder: "Rename Folder"
        case .newFolder(let moving): moving == nil ? "New Folder" : "New Folder and Move"
        case .trash(let item): "Move “\(item.title)” to the Trash?"
        case .trashFolder(let folder, _): "Move the folder “\(folder.name)” to the Trash?"
        case .folderNeedsReview(let folder, _): "“\(folder.name)” Has Other Files"
        case .failure(let title, _): title
        case nil: ""
        }
    }

    private func message(for prompt: LibraryPrompt) -> String {
        switch prompt {
        case .rename: return "Renames the folder and its Markdown file. The transcript itself is not changed."
        case .renameFolder: return "The transcripts inside keep their names and contents."
        case .newFolder: return "Creates a folder in the output folder."
        case .trash:
            return "The transcript and its timing data and audio go with it. You can restore it from the Trash."
        case .trashFolder(_, let entries):
            let count = entries == 1 ? "its 1 transcript" : "its \(entries) transcripts"
            return "The folder and \(count), with their timing data and audio, go with it. You can restore it from the Trash."
        case .folderNeedsReview(_, let names):
            let shown = names.prefix(4).map { "“\($0)”" }.joined(separator: ", ")
            let more = names.count > 4 ? " and \(names.count - 4) more" : ""
            return "It contains items Local Transcriber didn’t create: \(shown)\(more). Nothing was moved. Look through the folder in Finder first."
        case .failure(_, let reason): return reason
        }
    }
}

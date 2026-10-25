import SwiftUI
import AVFoundation
import AppKit
import UniformTypeIdentifiers

extension FocusedValues {
    @Entry var pasteLinks: WindowAction?
    @Entry var refreshTranscripts: WindowAction?
    @Entry var libraryCommands: LibraryCommands?
}

// A window's menu action. Every body pass publishes its focused values again, and a
// closure never equals the previous one: the menus would rebuild, the window would
// update and publish again, every frame, for as long as it is frontmost (LTR-68).
// So a value equals the last one from the same window, and the menu keeps calling
// the first action. That action reads the window's @State live, but any other view
// state (such as @AppStorage) as it was then: such state goes in `inputs`, so a
// change publishes a new action (LTR-70).
struct WindowAction: Equatable {
    let window: UUID
    var inputs: AnyHashable? = nil
    let perform: () -> Void

    func callAsFunction() { perform() }

    static func == (a: Self, b: Self) -> Bool { a.window == b.window && a.inputs == b.inputs }
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
    // The job's transcript was not saved; dismissing it loses the transcript.
    case discardUnsaved(TranscriptionJob)
}

struct ContentView: View {
    // Shared by all windows and Settings; owned by the app.
    let destination: OutputDestination
    // One queue for the whole app (see MyApp); every window shows and feeds it.
    let queue: BatchQueue
    @State private var recorder = Recorder()
    @State private var isTargeted = false
    @FocusState private var isImportZoneFocused: Bool
    @State private var notice: String?
    @State private var library = LibraryStore()
    @State private var selection: SidebarSelection? = .newTranscription
    // Bumped when the List deselects the selected row, so it draws the selection again.
    @State private var sidebarRefresh = 0
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    // The window's only audio player (see AudioReviewPlayer).
    @State private var player = AudioReviewPlayer()
    @State private var prompt: LibraryPrompt?
    @State private var promptText = ""
    // Tells this window's menu actions from another window's (see WindowAction).
    @State private var windowID = UUID()
    // Opens the transcript this window asked for once the request settles (LTR-72).
    @State private var autoOpen = ReviewAutoOpen()

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
                jobs: queue.jobs,
                processing: processingActions,
                recordingBanner: recorder.isIdle ? nil : AnyView(recordingStatus),
                library: library,
                destination: destination.status,
                selection: sidebarSelection,
                onNewTranscription: { userSelects(.newTranscription) },
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
        // Closing the window while it records asks first (RecordingCloseGuard).
        .background(RecordingCloseGuard(recorder: recorder))
        .dropDestination(for: URL.self) { urls, _ in
            addInput(urls)
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .focusedSceneValue(\.pasteLinks, WindowAction(window: windowID, perform: pasteFromClipboard))
        .focusedSceneValue(\.refreshTranscripts, WindowAction(window: windowID) { refreshLibrary() })
        .focusedSceneValue(\.libraryCommands, LibraryCommands(
            window: windowID, selected: selectedTranscript, canCreateFolder: destination.isReady, request: handle))
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
        // A saved job of this window's request, the queue settling and a rescan can each
        // be the last thing the automatic open waits for. A rescan also offers
        // recordings that were saved but never transcribed (after a quit, for example).
        .onChange(of: queue.lastSaved?.id) {
            if let job = queue.lastSaved, job.requester == windowID, let url = job.savedTranscriptURL {
                autoOpen.saved(url)
            }
            openFinishedTranscript()
        }
        .onChange(of: queue.isQuiet) { openFinishedTranscript() }
        .onChange(of: library.revision) {
            queue.offer(library.untranscribed)
            openFinishedTranscript()
        }
        // A transcript is new until it is opened: opening it (and only that) clears the badge.
        .onChange(of: selection) { _, new in markOpened(new) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLibrary()
        }
        // A selection that no longer exists (job joined to its library entry, item
        // removed outside the app, folder changed) goes back to New Transcription.
        .onChange(of: library.items) { selectionStillExists() }
        // Audio belongs to the open transcript only: any other selection silences it.
        .onChange(of: selection) { _, new in
            if let id = new?.transcriptID, player.itemID == id || player.isCarrying(to: id) { return }
            player.stop()
        }
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
                let inside = selection?.transcriptID?.hasPrefix(folder.url.libraryKey + "/") == true
                try library.trashFolder(folder)
                if inside { player.stop(); showNewTranscription() }
            }
        case .folderNeedsReview(let folder, _):
            NSWorkspace.shared.activateFileViewerSelecting([folder.url])
        case .discardUnsaved(let job):
            queue.dismiss(job)
        case .failure:
            break
        }
    }

    private func attempt(_ title: String, _ work: () throws -> Void) {
        do { try work() } catch { prompt = .failure(title: title, reason: error.localizedDescription) }
    }

    // A folder was renamed: an open transcript inside it follows to its new path.
    private func followFolder(_ old: LibraryFolder, to new: LibraryFolder) {
        let oldPath = old.url.libraryKey
        guard let current = selection, let id = current.transcriptID, id.hasPrefix(oldPath + "/") else { return }
        if player.itemID == id { player.stop() }
        selection = current.replacingTranscript(with: new.url.libraryKey + String(id.dropFirst(oldPath.count)))
    }

    // A renamed or moved transcript keeps its place in the sidebar and in the
    // queue; its audio is reloaded from the new path at the same position, playing
    // or paused as it was (AudioReviewPlayer.carryOver).
    private func follow(_ old: LibraryTranscript, to new: LibraryTranscript) {
        guard let current = selection, current.transcriptID == old.id else { return }
        player.carryOver(from: old.id, to: new.id)
        selection = current.replacingTranscript(with: new.id)
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
                userSelects(chosen)
            })
    }

    // A move the user made: a job finishing later must not take the window elsewhere.
    private func userSelects(_ chosen: SidebarSelection) {
        if chosen != selection { autoOpen.userNavigated() }
        selection = chosen
    }

    // Opens the transcript of this window's settled request once the library lists it.
    private func openFinishedTranscript() {
        let listed = Set(library.items.map(\.id))
        guard let url = autoOpen.transcriptToOpen(isQuiet: queue.isQuiet, isListed: { listed.contains($0.libraryKey) }) else { return }
        selection = .transcript(url.libraryKey)
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
            save: { job in
                if case .complete(let transcript, _) = job.state { saveTranscript(transcript, for: job) }
            },
            copy: { copyMarkdown(for: $0) },
            retry: { job in
                // The output folder may have gone since; say so instead of failing again.
                guard destination.isReady || destination.choose() else {
                    notice = "Choose an output folder to retry."
                    showNewTranscription()
                    return
                }
                queue.retry(job)
            },
            dismiss: { job in
                if case .complete = job.state, job.savedTranscriptURL == nil {
                    prompt = .discardUnsaved(job)
                } else {
                    queue.dismiss(job)
                }
            }
        )
    }

    private func markOpened(_ selection: SidebarSelection?) {
        guard let id = selection?.transcriptID,
              let item = library.items.first(where: { $0.id == id }), item.isNew else { return }
        try? library.markOpened(item)
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

    // New Transcription is one composer: mark and tagline above one surface, the
    // drop area on top and a compact record toolbar below it (LTR-55). Heights come
    // from the content. The work itself is listed in the sidebar's Processing section.
    private var content: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                BrandMark()
                BrandLine()
            }

            VStack(spacing: 0) {
                importZone
                Theme.rule.frame(height: 1).accessibilityHidden(true)
                recordBar
                    .background(Theme.raised)
            }
            .surface()
            .frame(maxWidth: 480)

            if hasMessages {
                messages(alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 560, maxHeight: .infinity)
        // Less vertical padding, so the footer stays in view at the minimum height.
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
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

    // The drop area and file picker, or, while an input waits for its language,
    // that question in the same place (LTR-72).
    @ViewBuilder
    private var importZone: some View {
        if let input = queue.pending.first {
            pendingZone(input)
        } else {
            dropZone
        }
    }

    private var importBackground: AnyShapeStyle {
        isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(Theme.recessed)
    }

    // The drop target is also the file picker.
    private var dropZone: some View {
        Button(action: chooseFiles) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.doc")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                    .accessibilityHidden(true)
                Text(isTargeted ? "Drop to add" : "Drop media here")
                    .font(.headline)
                Text("or click to choose files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("⌘V pastes media or a YouTube link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(importBackground)
            .contentShape(Rectangle())
        }
        // The system ring is drawn on the button's rectangle and would stick out
        // past the surface's rounded corners, so the zone draws it on its own shape.
        .focusEffectDisabled()
        .focused($isImportZoneFocused)
        .overlay {
            if isImportZoneFocused {
                UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
        .disabled(!recorder.isIdle)
        .accessibilityLabel("Choose files")
        .accessibilityHint("Or drop media, or press Command V to paste media or a YouTube link")
    }

    // Which input waits, and one menu whose choice starts it: no language is
    // preselected and there is no Start button. Drops and ⌘V still add more.
    private func pendingZone(_ input: PendingInput) -> some View {
        VStack(spacing: 6) {
            Text("Which language is spoken in")
                .font(.caption)
                .foregroundStyle(.secondary)
            // Two lines: a recording is told apart by the time in its long name.
            Text(input.name)
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(input.name)
            if input.recording != nil {
                Text("Saved in your library folder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Prominent like Home: this is the one thing to do here. A recent language
            // is listed once, under Recent.
            Menu("Choose Language") {
                let recent = queue.recentLanguages
                let others = TranscriptionLanguage.byTitle.filter { !recent.contains($0) }
                if recent.isEmpty {
                    languageButtons(others, for: input)
                } else {
                    Section("Recent") { languageButtons(recent, for: input) }
                    Section("All Languages") { languageButtons(others, for: input) }
                }
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10))   // Home's shape
            .controlSize(.large)
            .fixedSize()
            .padding(.vertical, 2)
            .accessibilityLabel("Choose the language spoken in \(input.name)")

            HStack(spacing: 10) {
                Button("Remove") { queue.discard(input) }
                    .help(input.recording != nil
                          ? "Don’t transcribe it now. The recording stays in your library folder."
                          : "Don’t transcribe it. The original is not changed.")
                Button("Add Files…", action: chooseFiles)
                if queue.pending.count > 1 {
                    Text("\(queue.pending.count - 1) more waiting")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(importBackground)
    }

    private func languageButtons(_ languages: [TranscriptionLanguage], for input: PendingInput) -> some View {
        ForEach(languages) { language in
            Button(language.title) { start(input, in: language) }
        }
    }

    // Record is one more input: the finished recording is saved to the output
    // folder and then queued exactly like a dropped file. The choice is made
    // inline; nothing is captured or requested before Record.
    // One row: the label, the sources together, Record apart at the trailing edge.
    private var recordBar: some View {
        HStack(spacing: 12) {
            Text(isRecording ? "Recording" : "Record audio")
                .font(.headline)
                .fixedSize()
                .accessibilityAddTraits(.isHeader)
            Group {
                if recorder.isIdle {
                    HStack(spacing: 8) {
                        // Its own width, up to 200: a longer name truncates.
                        appPicker
                            .frame(maxWidth: 200)
                            .fixedSize()
                        micToggle
                        Spacer(minLength: 8)
                        recordButton
                    }
                } else {
                    recordingStatus
                }
            }
            // The picker's height, so the row keeps its size while starting, recording and saving.
            .frame(minHeight: 24)
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var isRecording: Bool {
        if case .recording = recorder.state { true } else { false }
    }

    private var appPicker: some View {
        Picker("App audio", selection: $recorder.selectedAppID) {
            Text("No app audio").tag(String?.none)
            Divider()
            ForEach(recorder.apps) { app in
                Text(app.name).tag(String?.some(app.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        // The full name of a selected app, which the picker may truncate.
        .help(recorder.apps.first { $0.id == recorder.selectedAppID }?.name ?? "")
    }

    private var micToggle: some View {
        Toggle("Mic", isOn: $recorder.includesMicrophone)
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityLabel("Include microphone")
    }

    // No ready folder while running work uses it: choose() refuses its panel,
    // so Record or Transcribe would silently do nothing. The footer says why.
    private var folderBlocked: Bool { !destination.isReady && !destination.canChangeFolder }
    private static let folderBlockedNotice = "The output folder is unavailable. Choose another one when the running work finishes."

    private var recordButton: some View {
        Button("Record", action: startRecording)
            .disabled(!recorder.canRecord || folderBlocked || destination.isRecording)
            .help(destination.isRecording ? "Another window is recording." : "")
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

    // One row, in the composer's record toolbar and in the sidebar's Recording section.
    @ViewBuilder
    private var recordingStatus: some View {
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
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                // The header says Recording. The source gives way first; the
                // time and Stop always fit the sidebar.
                Text(recorder.recordingLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text(since, style: .timer)
                    .font(.body.monospacedDigit())
                    .fixedSize()
                Button {
                    Task { await recorder.stop() }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .help("Stop Recording")
                .accessibilityLabel("Stop Recording")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Recording")
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
            .disabled(!destination.canChangeFolder)
        }
    }

    // The recording was saved as an entry folder holding its audio; once its language
    // is chosen, the transcript is written into that same folder. Until then (and if
    // the app quits first) the audio stays there, an entry the library skips.
    private func addRecording(_ url: URL, startedAt: Date) {
        _ = addInput([url], recording: (url.deletingLastPathComponent(), startedAt))
    }

    // Same path as a drop; the panel offers only the extensions a drop accepts.
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK else { return }
        _ = addInput(panel.urls)
    }

    // Status, not controls: the destination reads quietly here, and preferences
    // live in Settings. The language belongs to each input (LTR-72), not here.
    private var footer: some View {
        HStack(spacing: 16) {
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

    private var folderLockReason: String {
        destination.isRecording ? "The output folder can’t change while recording."
                                : "The output folder can’t change while the queue is running."
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
                let path = url.path(percentEncoded: false)
                Button {
                    destination.choose()
                } label: {
                    Text("Saves to \(url.lastPathComponent)…")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .buttonStyle(.link)
                .disabled(!destination.canChangeFolder)
                .help(destination.canChangeFolder ? "\(path)\nClick to choose another folder." : "\(path)\n\(folderLockReason)")
                .accessibilityValue(path)
                .accessibilityHint(destination.canChangeFolder ? "Chooses another output folder." : folderLockReason)
                .contextMenu {
                    // Reveal never changes the destination, so it stays available while locked.
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
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

    // The one way inputs reach the queue (drop, ⌘V, the file panel, a saved
    // recording). Supported files and YouTube links wait, in order, for their
    // language on New Transcription; nothing starts here. Anything unsupported is
    // reported with the reason and not added.
    @discardableResult
    private func addInput(_ urls: [URL], recording: (folder: URL, startedAt: Date)? = nil) -> Bool {
        notice = nil
        var sources: [JobSource] = []
        for url in urls {
            if url.isFileURL {
                guard supportedExtensions.contains(url.pathExtension.lowercased()) else {
                    notice = "Not supported. Drop an MP4, MOV, M4A, MP3 or WAV file, or a YouTube link."
                    continue
                }
                sources.append(.file(url))
            } else if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                guard let video = YouTubeURL.parse(url) else {
                    prompt = .failure(title: "Only YouTube links are supported", reason: url.absoluteString)
                    continue
                }
                sources.append(.youtube(videoID: video.videoID, url: video.canonical))
            } else {
                notice = "Not supported. Drop an MP4, MOV, M4A, MP3 or WAV file, or a YouTube link."
            }
        }
        // The notice and the language choice live on the input surface.
        showNewTranscription()
        guard !sources.isEmpty else { return false }

        // No usable output folder yet: ask once; cancelling adds nothing.
        guard destination.isReady || destination.choose() else {
            notice = folderBlocked ? Self.folderBlockedNotice : "Choose an output folder to start transcribing."
            return false
        }

        for source in sources { queue.stage(source, recording: recording) }
        return true
    }

    // The language was chosen for this input: it becomes a job and starts, or waits
    // for the jobs before it. This window opens the transcript when the request settles.
    private func start(_ input: PendingInput, in language: TranscriptionLanguage) {
        autoOpen.languageChosen()
        guard let job = queue.start(input, language: language, requester: windowID) else { return }
        if case .file(let url) = job.source {
            Task { job.mediaInfo = await loadMediaInfo(for: url) }
        }
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
        addInput(urls)
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

    // Read-only: puts the job's Markdown on the pasteboard, without its YAML
    // frontmatter (LTR-37). The result tells the row whether it may show "Copied".
    private static let copyFailedNotice = "Could not copy the transcript to the clipboard."

    private func copyMarkdown(for job: TranscriptionJob) -> Bool {
        guard case .complete(let transcript, _) = job.state else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(TranscriptMarkdown.withoutFrontmatter(job.markdown(for: transcript)), forType: .string) else {
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
            queue.dismiss(job)   // saved by hand: the slot is free again
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            notice = nil
        } catch {
            job.savedTranscriptURL = nil
            notice = error.localizedDescription
        }
    }
}

// The brand mark: the SF Symbol waveform (LTR-55). Static and decorative.
private struct BrandMark: View {
    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 44, weight: .medium))
            .foregroundStyle(.primary)
            // The former mark's height, so the spacing to the headline stays.
            .frame(height: 52)
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

    // The language menu's full list.
    static let byTitle = allCases.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

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
            case .discardUnsaved:
                Button("Discard Transcript", role: .destructive) { commit(current) }
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
        case .discardUnsaved: "Discard the unsaved transcript?"
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
        case .discardUnsaved(let job):
            return "“\(job.displayName)” was transcribed but not saved. Use Save Transcript… to keep it; dismissing it loses the transcript."
        case .failure(_, let reason): return reason
        }
    }
}

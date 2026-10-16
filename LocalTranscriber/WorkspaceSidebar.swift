import AppKit
import SwiftUI

// What the sidebar has selected. New Transcription and an In progress job both
// show the queue; a transcript shows the Review view. A pinned transcript is
// listed twice (Pinned and its folder): the two rows are one transcript, and
// `.pinned` only says which row carries the highlight.
enum SidebarSelection: Hashable {
    case newTranscription
    case job(UUID)
    case transcript(LibraryTranscript.ID)
    case pinned(LibraryTranscript.ID)

    var transcriptID: LibraryTranscript.ID? {
        switch self {
        case .transcript(let id), .pinned(let id): id
        case .newTranscription, .job: nil
        }
    }

    // The same kind of row for another transcript (after a rename or move).
    func replacingTranscript(with id: LibraryTranscript.ID) -> SidebarSelection {
        if case .pinned = self { .pinned(id) } else { .transcript(id) }
    }
}

// What a menu, a key or the Transcript menu asks the library to do. The window
// carries it out (it owns the prompts, the selection and the player).
enum LibraryRequest {
    case rename(LibraryTranscript)
    case togglePin(LibraryTranscript)
    case toggleArchive(LibraryTranscript)
    // `nil` moves the entry out of its folder, to the top level.
    case move(LibraryTranscript, to: LibraryFolder?)
    case newFolder(moving: LibraryTranscript?)
    case trash(LibraryTranscript)
    case renameFolder(LibraryFolder)
    case trashFolder(LibraryFolder)
}

// What the Transcript menu can act on: the open transcript, if any.
struct LibraryCommands {
    var selected: LibraryTranscript?
    var canCreateFolder: Bool
    var request: (LibraryRequest) -> Void
}

// One sidebar for the live queue and the saved transcripts (doc-3). Native list
// and sidebar styling; sentence-case section headers; no custom selection colour.
// Library: Pinned, Folders (real folders), Recent (not in a folder), Archive.
struct WorkspaceSidebar: View {
    let jobs: [TranscriptionJob]
    let library: LibraryStore
    let destination: OutputDestination.Status
    @Binding var selection: SidebarSelection?
    let onNewTranscription: () -> Void
    let onRefresh: () -> Void
    let onRequest: (LibraryRequest) -> Void

    @State private var collapsedFolders: Set<String> = []
    @State private var archiveExpanded = false

    var body: some View {
        let sections = library.sections
        List(selection: $selection) {
            // The queue pane already shows these; the sidebar lists them when
            // another view is open, so they stay reachable.
            if !jobs.isEmpty && selection != .newTranscription {
                Section("In progress") {
                    ForEach(jobs) { job in
                        SidebarJobRow(job: job)
                            .tag(SidebarSelection.job(job.id))
                    }
                }
            }

            if !sections.pinned.isEmpty {
                Section("Pinned") {
                    ForEach(sections.pinned) { item in
                        row(item, showsFolder: true, tag: .pinned(item.id))
                    }
                }
            }

            if !sections.recent.isEmpty || library.items.isEmpty && sections.folders.isEmpty {
                Section {
                    if library.items.isEmpty {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .selectionDisabled()
                            .contextMenu { refreshMenu }
                    } else {
                        ForEach(sections.recent) { row($0, showsFolder: false, tag: .transcript($0.id)) }
                    }
                } header: {
                    // A header's menu covers only the header, so the rows carry it too.
                    Text("Recent")
                        .contextMenu { refreshMenu }
                }
            }

            if !sections.folders.isEmpty {
                Section("Folders") {
                    ForEach(sections.folders, id: \.folder.id) { folderRow($0) }
                }
            }

            if !sections.archived.isEmpty {
                Section("Archive", isExpanded: $archiveExpanded) {
                    ForEach(sections.archived) { row($0, showsFolder: true, tag: .transcript($0.id)) }
                }
            }
        }
        .listStyle(.sidebar)
        // One warm ground for both appearances (see Theme.sidebar).
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) { newButton }
        .accessibilityLabel("Transcription sidebar")
        // The Delete key asks to move the selected transcript to the Trash.
        .onDeleteCommand {
            if let id = selection?.transcriptID,
               let item = library.items.first(where: { $0.id == id }), item.isManaged {
                onRequest(.trash(item))
            }
        }
    }

    // One click starts a new transcription; the menu holds the other things
    // that can be created (more can be added here later).
    private var newButton: some View {
        Menu {
            Button("New Transcription", systemImage: "waveform.badge.plus", action: onNewTranscription)
            Button("New Folder…", systemImage: "folder.badge.plus") { onRequest(.newFolder(moving: nil)) }
        } label: {
            Label("New Transcription", systemImage: "plus")
                .frame(maxWidth: .infinity)
        } primaryAction: {
            onNewTranscription()
        }
        .menuStyle(.button)
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.sidebar)
    }

    private func row(_ item: LibraryTranscript, showsFolder: Bool, tag: SidebarSelection) -> some View {
        SidebarTranscriptRow(item: item, showsFolder: showsFolder)
            .tag(tag)
            .contextMenu { entryMenu(item) }
    }

    private func folderRow(_ group: LibrarySections.Group) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !collapsedFolders.contains(group.folder.id) },
            set: { open in
                if open { collapsedFolders.remove(group.folder.id) } else { collapsedFolders.insert(group.folder.id) }
            })
        ) {
            ForEach(group.entries) { row($0, showsFolder: false, tag: .transcript($0.id)) }
        } label: {
            Label(group.folder.name, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .contextMenu {
                    Button("Rename Folder…") { onRequest(.renameFolder(group.folder)) }
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([group.folder.url])
                    }
                    Divider()
                    Button("Move to Trash…", role: .destructive) { onRequest(.trashFolder(group.folder)) }
                }
        }
    }

    @ViewBuilder
    private func entryMenu(_ item: LibraryTranscript) -> some View {
        if item.isManaged {
            Button("Rename…") { onRequest(.rename(item)) }
            Button(item.isPinned ? "Unpin" : "Pin") { onRequest(.togglePin(item)) }
            Button(item.isArchived ? "Unarchive" : "Archive") { onRequest(.toggleArchive(item)) }
            Menu("Move to") {
                if item.group != nil {
                    Button("No Folder") { onRequest(.move(item, to: nil)) }
                }
                ForEach(library.folders.filter { $0.url.standardizedFileURL != item.group?.standardizedFileURL }) { folder in
                    Button(folder.name) { onRequest(.move(item, to: folder)) }
                }
                Divider()
                Button("New Folder…") { onRequest(.newFolder(moving: item)) }
            }
            Divider()
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([item.markdownURL])
        }
        if item.isManaged {
            Button("Move to Trash…", role: .destructive) { onRequest(.trash(item)) }
        }
        Divider()
        refreshMenu
    }

    // The same refresh as View › Refresh Transcripts (⌘R).
    private var refreshMenu: some View {
        Button("Refresh Transcripts", action: onRefresh)
    }

    // Quiet and specific: it says why the list is empty, and what fills it.
    private var emptyMessage: String {
        switch destination {
        case .none:
            "Choose an output folder to see saved transcripts here."
        case .unavailable:
            "The output folder is unavailable, so its transcripts can’t be listed."
        case .ready:
            if let error = library.loadError {
                "Couldn’t read the output folder: \(error)"
            } else if library.isLoading {
                "Looking for transcripts…"
            } else {
                "Transcripts saved in this folder appear here."
            }
        }
    }
}

private struct SidebarJobRow: View {
    let job: TranscriptionJob

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(job.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                status
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        switch job.state {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading, .transcribing:
            ProgressView().controlSize(.small)
        case .complete:
            // Listed here only until its library entry appears, or when its save failed.
            job.savedTranscriptURL == nil
                ? Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                : Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch job.state {
        case .waiting:
            Text("Waiting").foregroundStyle(.secondary)
        case .downloading:
            Text("Downloading…").foregroundStyle(.secondary)
        case .transcribing(let phase):
            Text(phase?.label ?? "Transcribing…").foregroundStyle(.secondary)
        case .complete:
            Text(job.savedTranscriptURL == nil ? "Not saved" : "Complete").foregroundStyle(.secondary)
        case .failed:
            Text("Failed").foregroundStyle(.red)
        }
    }
}

private struct SidebarTranscriptRow: View {
    let item: LibraryTranscript
    // Pinned and archived entries are listed away from their folder, so they say where it is.
    let showsFolder: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .help(item.createdAt.map { "Created \($0.formatted(date: .long, time: .shortened))" }
            ?? "Saved \(item.savedAt.formatted(date: .long, time: .shortened))")
        .accessibilityElement(children: .combine)
    }

    // Folder (when away from it), the creation date (else the save date), then the length.
    private var detail: String {
        var parts: [String] = []
        if showsFolder, let group = item.group { parts.append(group.lastPathComponent) }
        parts.append(item.sortDate.formatted(date: .abbreviated, time: .shortened))
        if let duration = item.header.duration { parts.append(TimestampFormat.string(duration)) }
        return parts.joined(separator: " · ")
    }
}

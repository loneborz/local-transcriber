import AppKit
import SwiftUI

// What the sidebar has selected. New Transcription and an In progress job both
// show the queue; a transcript shows the Review view.
enum SidebarSelection: Hashable {
    case newTranscription
    case job(UUID)
    case transcript(LibraryTranscript.ID)
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
    let onRefresh: () -> Void
    let onRequest: (LibraryRequest) -> Void

    @State private var collapsedFolders: Set<String> = []
    @State private var archiveExpanded = false

    private var isReady: Bool {
        if case .ready = destination { true } else { false }
    }

    var body: some View {
        let sections = library.sections
        List(selection: $selection) {
            Label("New Transcription", systemImage: "plus")
                .tag(SidebarSelection.newTranscription)

            if !jobs.isEmpty {
                Section("In progress") {
                    ForEach(jobs) { job in
                        SidebarJobRow(job: job)
                            .tag(SidebarSelection.job(job.id))
                    }
                }
            }

            if !sections.pinned.isEmpty {
                Section("Pinned") { rows(sections.pinned, showsFolder: true) }
            }

            if isReady {
                Section {
                    if sections.folders.isEmpty {
                        Text("Folders you create appear here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                            .contextMenu { newFolderMenu }
                    }
                    ForEach(sections.folders, id: \.folder.id) { group in folderRow(group) }
                } header: {
                    HStack {
                        Text("Folders")
                        Spacer()
                        Button { onRequest(.newFolder(moving: nil)) } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .buttonStyle(.borderless)
                        .help("New Folder")
                        .accessibilityLabel("New Folder")
                    }
                    .contextMenu { newFolderMenu }
                }
            }

            if !sections.recent.isEmpty || library.items.isEmpty {
                Section {
                    if library.items.isEmpty {
                        Text(emptyMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .selectionDisabled()
                            .contextMenu { refreshMenu }
                    } else {
                        rows(sections.recent, showsFolder: false)
                    }
                } header: {
                    // A header's menu covers only the header, so the rows carry it too.
                    Text("Recent")
                        .contextMenu { refreshMenu }
                }
            }

            if !sections.archived.isEmpty {
                Section("Archive", isExpanded: $archiveExpanded) { rows(sections.archived, showsFolder: true) }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Transcription sidebar")
        // The Delete key asks to move the selected transcript to the Trash.
        .onDeleteCommand {
            if case .transcript(let id) = selection,
               let item = library.items.first(where: { $0.id == id }), item.isManaged {
                onRequest(.trash(item))
            }
        }
    }

    private func rows(_ items: [LibraryTranscript], showsFolder: Bool) -> some View {
        ForEach(items) { item in
            SidebarTranscriptRow(item: item, showsFolder: showsFolder)
                .tag(SidebarSelection.transcript(item.id))
                .contextMenu { entryMenu(item) }
        }
    }

    private func folderRow(_ group: LibrarySections.Group) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { !collapsedFolders.contains(group.folder.id) },
            set: { open in
                if open { collapsedFolders.remove(group.folder.id) } else { collapsedFolders.insert(group.folder.id) }
            })
        ) {
            if group.entries.isEmpty {
                Text("No transcripts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .selectionDisabled()
            }
            rows(group.entries, showsFolder: false)
        } label: {
            Label(group.folder.name, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
                .contextMenu {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([group.folder.url])
                    }
                    Divider()
                    newFolderMenu
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

    private var newFolderMenu: some View {
        Button("New Folder…") { onRequest(.newFolder(moving: nil)) }
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

import SwiftUI

// What the sidebar has selected. New Transcription and an In progress job both
// show the queue; a transcript shows the Review view.
enum SidebarSelection: Hashable {
    case newTranscription
    case job(UUID)
    case transcript(LibraryTranscript.ID)
}

// One sidebar for the live queue and the saved transcripts (doc-3). Native list
// and sidebar styling; sentence-case section headers; no custom selection colour.
struct WorkspaceSidebar: View {
    let jobs: [TranscriptionJob]
    let library: LibraryStore
    let destination: OutputDestination.Status
    @Binding var selection: SidebarSelection?
    let onRefresh: () -> Void

    var body: some View {
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

            Section {
                if library.items.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .selectionDisabled()
                        .contextMenu { refreshMenu }
                } else {
                    ForEach(library.items) { item in
                        SidebarTranscriptRow(item: item)
                            .tag(SidebarSelection.transcript(item.id))
                            .contextMenu { refreshMenu }
                    }
                }
            } header: {
                // A header's menu covers only the header, so the rows carry it too.
                Text("Transcripts")
                    .contextMenu { refreshMenu }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Transcription sidebar")
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
        .help("Saved \(item.savedAt.formatted(date: .long, time: .shortened))")
        .accessibilityElement(children: .combine)
    }

    // "Saved" date, then the length when the header has one.
    private var detail: String {
        var parts = [item.savedAt.formatted(date: .abbreviated, time: .shortened)]
        if let duration = item.header.duration { parts.append(TimestampFormat.string(duration)) }
        return parts.joined(separator: " · ")
    }
}

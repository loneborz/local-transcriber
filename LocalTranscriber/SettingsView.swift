import AppKit
import SwiftUI

// A page of the Settings window. Which one shows is kept in memory only (MyApp), so
// the missing-model guidance can open Models; no preference is added for it.
enum SettingsPage: Hashable {
    case general, models, output
}

// The one Settings window (app menu Settings…, ⌘, and the footer entry): native tabs
// (doc-3 Addendum 9). Controls that would change something a running job or recording
// depends on are locked app-wide while it runs (see OutputDestination), with a note
// that says why.
struct SettingsView: View {
    let destination: OutputDestination
    @Binding var page: SettingsPage

    var body: some View {
        TabView(selection: $page) {
            Tab("General", systemImage: "gearshape", value: SettingsPage.general) {
                GeneralSettings()
            }
            Tab("Models", systemImage: "waveform", value: SettingsPage.models) {
                ModelsSettings()
            }
            Tab("Output", systemImage: "folder", value: SettingsPage.output) {
                OutputSettings(destination: destination)
            }
        }
        .frame(width: 480)
        // Here and not on the Whisper section, so it runs when the window opens, as
        // before: switching pages must not replace a failed download's reason.
        .onAppear { WhisperModelStore.shared.refresh() }
    }
}

private struct GeneralSettings: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: appearance) { AppAppearance.apply() }
        }
        .padding(20)
    }
}

private struct ModelsSettings: View {
    // Never locked: a job keeps the engine it was enqueued with (LTR-82).
    @AppStorage(TranscriptionEngine.preferenceKey) private var engine = TranscriptionEngine.appleSpeech

    var body: some View {
        Form {
            Picker("Transcription Engine", selection: $engine) {
                ForEach(TranscriptionEngine.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            note("Engine changes apply when an input is added to the queue. Already queued or running jobs keep their assigned engine.")
            note("Apple Speech is built into macOS. macOS manages its language files and may download one the first time a language is used.")

            WhisperSettings()
        }
        .padding(20)
    }
}

private struct OutputSettings: View {
    let destination: OutputDestination
    @AppStorage(BatchQueue.sourcePackageModeKey) private var savesSourcePackages = false
    @AppStorage(BatchQueue.frontmatterKey) private var addsFrontmatter = false

    var body: some View {
        Form {
            // Read-only: the footer stays the one place to change the folder (LTR-64).
            LabeledContent("Output Folder") {
                switch destination.status {
                case .none:
                    Text("Not chosen")
                case .ready(let url):
                    let path = url.path(percentEncoded: false)
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                case .unavailable(let message):
                    Text(message)
                        .foregroundStyle(.red)
                }
            }
            // Reveal never changes the destination, so it stays available while locked.
            if let folder = destination.readyFolder {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
                .accessibilityLabel("Reveal output folder in Finder")
            }
            note("Change the output folder in the footer of the main window.")

            Toggle("Save YouTube Links as Source Packages", isOn: $savesSourcePackages)
                .disabled(!destination.canChangeSourcePackage)

            // Read when a transcript is saved, so it never needs a lock.
            Toggle("Add YAML Frontmatter to New Transcripts", isOn: $addsFrontmatter)

            if let lockNote {
                note(lockNote)
            }
        }
        .padding(20)
    }

    private var lockNote: String? {
        destination.isTranscribing ? "This setting can’t change while the queue is running." : nil
    }
}

// The optional Whisper Large V3 Turbo model (LTR-76, doc-3 Addendum 8 D2-D4, D8):
// status, the user-started download, disk use and removal.
private struct WhisperSettings: View {
    @State private var confirmsRemoval = false
    @State private var removalError: String?
    private var store: WhisperModelStore { .shared }

    var body: some View {
        Section("Whisper Large V3 Turbo") {
            LabeledContent("Model", value: status)

            switch store.state {
            case .downloading(let received, let total):
                ProgressView(value: Double(received), total: Double(total)) {
                    Text("\(received.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))")
                        .font(.caption)
                        .monospacedDigit()
                }
                Button("Cancel Download") { store.cancel() }
            case .verifying:
                ProgressView().controlSize(.small)
            case .installed:
                if let usage = store.diskUsage {
                    LabeledContent("Disk use", value: usage.formatted(.byteCount(style: .file)))
                }
                // The Core ML compile cache is the system's; its size is not shown (LTR-76 F2).
                note("The size of the downloaded model. macOS may also keep a compiled copy in its own caches, which Remove doesn’t delete.")
                Button("Remove…") { confirmsRemoval = true }
                    .disabled(store.isInUse)
                if store.isInUse {
                    note("The model can’t be removed while a Whisper job is waiting or running.")
                }
            case .notInstalled, .failed:
                Button("Download (\(store.totalBytes.formatted(.byteCount(style: .file))))") { store.download() }
                note("Downloaded from Hugging Face (argmaxinc/whisperkit-coreml, a fixed version) only when you choose Download, and checked file by file. Transcription itself never uses the network.")
            }

            if let removalError { note(removalError) }
        }
        .alert("Remove Whisper Large V3 Turbo?", isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive) {
                do { try store.remove() } catch { removalError = error.localizedDescription }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The downloaded model files are deleted from this Mac. A compiled copy that macOS keeps in its own caches may remain. Transcripts and media stay as they are. You can download the model again later.")
        }
    }

    private var status: String {
        switch store.state {
        case .notInstalled: "Not installed"
        case .downloading: "Downloading"
        case .verifying: "Verifying"
        case .installed where store.isPreparing: "Preparing"
        case .installed where store.isPrepared: "Ready"
        case .installed: "Installed, prepared at first use"
        case .failed(let reason): "Failed: \(reason)"
        }
    }
}

private func note(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}

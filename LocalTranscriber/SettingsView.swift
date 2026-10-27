import SwiftUI

// The one Settings window (app menu Settings…, ⌘, and the footer entry). Native
// look: a single Form today (the default language and the output folder live in the footer, next to
// where they are used); a second category would bring back a TabView. Controls that would change
// something a running job or recording depends on are locked app-wide while it
// runs (see OutputDestination), with a note that says why.
struct SettingsView: View {
    let destination: OutputDestination

    var body: some View {
        GeneralSettings(destination: destination)
            .frame(width: 480)
    }
}

private struct GeneralSettings: View {
    let destination: OutputDestination
    @AppStorage(BatchQueue.sourcePackageModeKey) private var savesSourcePackages = false
    @AppStorage(BatchQueue.frontmatterKey) private var addsFrontmatter = false
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: appearance) { AppAppearance.apply() }

            Toggle("Save YouTube Links as Source Packages", isOn: $savesSourcePackages)
                .disabled(!destination.canChangeSourcePackage)

            // Read when a transcript is saved, so it never needs a lock.
            Toggle("Add YAML Frontmatter to New Transcripts", isOn: $addsFrontmatter)

            if let lockNote {
                Text(lockNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            WhisperSettings()
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
        .onAppear { store.refresh() }
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

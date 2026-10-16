import SwiftUI

@main struct MyApp: App {
    init() {
        // Nothing is running yet, so anything in the acquisition directory is
        // left over from a crashed or killed run. Children are also terminated
        // on a normal quit.
        YouTubeAcquirer.sweepStaleDirectories()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            HelperProcess.terminateAll()
        }
    }

    // One output folder for all windows and Settings (see OutputDestination).
    @State private var destination = OutputDestination()

    @FocusedValue(\.pasteLinks) private var pasteLinks
    @FocusedValue(\.refreshTranscripts) private var refreshTranscripts

    var body: some Scene {
        WindowGroup {
            ContentView(destination: destination)
        }
        .commands {
            // The window has no text field, so the standard Paste is always
            // disabled and would swallow ⌘V. This Paste adds a copied YouTube
            // link or media file instead; Copy keeps working for selectable text.
            CommandGroup(replacing: .pasteboard) {
                Button("Copy") {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("c")

                Button("Paste") { pasteLinks?() }
                    .keyboardShortcut("v")
                    .disabled(pasteLinks == nil)
            }

            // Looks for transcripts in the output folder again (also automatic
            // on launch, folder change, save and app activation, and in the
            // sidebar's Transcripts context menu).
            CommandGroup(after: .toolbar) {
                Button("Refresh Transcripts") { refreshTranscripts?() }
                    .keyboardShortcut("r")
                    .disabled(refreshTranscripts == nil)
            }
        }

        // The app menu's Settings… item and ⌘, come with this scene; the footer
        // entry opens the same window.
        Settings {
            SettingsView(destination: destination)
        }
    }
}

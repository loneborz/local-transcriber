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

    @FocusedValue(\.pasteLinks) private var pasteLinks

    var body: some Scene {
        WindowGroup {
            ContentView()
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
        }
    }
}

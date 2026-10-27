// swift-tools-version: 6.2
import PackageDescription

// Test foundation only: `swift test` compiles the pure, Apple-Speech-free files
// that already live in the app's folder (no copy, no Xcode project change, no
// test code in the app target). The app itself is built by the Xcode project.
let package = Package(
    name: "TranscriptCore",
    platforms: [.macOS(.v26)],
    // The app's WhisperKit pin (Xcode Package.resolved: 1.1.1, 1bbc57cb), for
    // the local tokenizer's parity and fail-closed tests.
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", exact: "1.1.1"),
    ],
    targets: [
        .target(
            name: "TranscriptCore",
            dependencies: [.product(name: "WhisperKit", package: "argmax-oss-swift")],
            path: "LocalTranscriber",
            // YouTubeSource.swift is only here for SourceMetadata, which the
            // renderer takes for source packages. WhisperModelStore.swift is
            // Foundation-only and here for its install and removal tests.
            // WhisperLocalTokenizer.swift is here for its tokenizer tests.
            exclude: [
                "Assets.xcassets", "AudioReviewPlayer.swift", "BatchQueue.swift", "ContentView.swift", "Credits.rtf",
                "LibraryStore.swift", "MyApp.swift", "OutputDestination.swift", "Recorder.swift", "RecordingCloseGuard.swift",
                "SettingsView.swift", "SourcePackage.swift", "Theme.swift", "TranscriptReviewView.swift",
                "TranscriptionService.swift", "WhisperDeveloperMenu.swift", "WhisperTranscriptionService.swift",
                "WorkspaceSidebar.swift",
            ],
            sources: ["Transcript", "YouTubeSource.swift", "WhisperModelStore.swift", "WhisperLocalTokenizer.swift"],
            // Same as the app target (SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor).
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "TranscriptCoreTests",
            dependencies: ["TranscriptCore", .product(name: "WhisperKit", package: "argmax-oss-swift")],
            path: "Tests/TranscriptCoreTests",
            exclude: ["Fixtures"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v5]
)

import AVFoundation
import XCTest
@testable import TranscriptCore

// LTR-76: YouTube's fragmented M4A states its full length in the header, and
// AVFoundation then reports twice the audio, so Review refused the kept file.
// The fixture is a 2 s generated tone, fragmented and given such a header.
final class YouTubeAudioTests: XCTestCase {
    private func durations(_ url: URL) async throws -> (asset: Double, audio: Double) {
        let asset = try await AVURLAsset(url: url).load(.duration).seconds
        let file = try AVAudioFile(forReading: url)
        return (asset, Double(file.length) / file.processingFormat.sampleRate)
    }

    func testRewrittenContainerReportsTheAudioOnce() async throws {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/fragmented-dash", withExtension: "m4a"))
        let before = try await durations(source)
        XCTAssertGreaterThan(before.asset, before.audio * 1.8, "fixture no longer shows the doubled length")
        XCTAssertFalse(AudioResolution.durationsAgree(audio: before.asset, transcript: before.audio))

        let output = FileManager.default.temporaryDirectory.appending(path: "rewritten-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: output) }
        try await YouTubeAcquirer.rewriteContainer(of: source, to: output)
        let after = try await durations(output)
        XCTAssertEqual(after.asset, after.audio, accuracy: 0.001)
        XCTAssertEqual(after.audio, before.audio, accuracy: 0.05)
        XCTAssertTrue(AudioResolution.durationsAgree(audio: after.asset, transcript: after.audio))
    }
}

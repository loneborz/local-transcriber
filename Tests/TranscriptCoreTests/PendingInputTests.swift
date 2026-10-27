import XCTest
@testable import TranscriptCore

// The engine belongs to one waiting input and is fixed when it starts (LTR-76, D1).
final class PendingInputTests: XCTestCase {
    private func file(_ name: String) -> JobSource { .file(URL(fileURLWithPath: "/tmp/\(name)")) }

    func testAppleSpeechIsTheDefault() {
        XCTAssertEqual(PendingInput(source: file("a.m4a"), recording: nil).engine, .appleSpeech)
    }

    func testEachInputHasItsOwnEngine() {
        var pending = [PendingInput(source: file("a.m4a"), recording: nil), PendingInput(source: file("b.mp4"), recording: nil),
                       PendingInput(source: .youtube(videoID: "x", url: URL(string: "https://youtu.be/x")!), recording: nil)]
        pending.setEngine(.whisper, for: pending[1].id)
        XCTAssertEqual(pending.map(\.engine), [.appleSpeech, .whisper, .appleSpeech])
        pending.setEngine(.whisper, for: pending[2].id)
        pending.setEngine(.appleSpeech, for: pending[1].id)
        XCTAssertEqual(pending.map(\.engine), [.appleSpeech, .appleSpeech, .whisper])
    }

    func testAStartedInputKeepsItsEngine() throws {
        var pending = [PendingInput(source: file("a.m4a"), recording: nil), PendingInput(source: file("b.m4a"), recording: nil)]
        let first = pending[0].id
        pending.setEngine(.whisper, for: first)
        let started = try XCTUnwrap(pending.take(first))
        XCTAssertEqual(started.engine, .whisper)
        XCTAssertNil(pending.take(first))
        // A later change from the interface finds nothing to change.
        pending.setEngine(.appleSpeech, for: first)
        XCTAssertEqual(started.engine, .whisper)
        XCTAssertEqual(pending.map(\.engine), [.appleSpeech])
    }

    func testARecordingKeepsItsEngineAndFolder() throws {
        let folder = URL(fileURLWithPath: "/tmp/Recording 1", isDirectory: true)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var pending = [PendingInput(source: file("Recording 1/Recording 1.m4a"), recording: (folder, startedAt))]
        pending.setEngine(.whisper, for: pending[0].id)
        let started = try XCTUnwrap(pending.take(pending[0].id))
        XCTAssertEqual(started.engine, .whisper)
        XCTAssertEqual(started.recording?.folder, folder)
        XCTAssertEqual(started.recording?.startedAt, startedAt)
    }

    func testAFailingWhisperRunNeverReachesAppleSpeech() async {
        struct WhisperFailed: Error {}
        let calls = Calls()
        typealias Run = @Sendable () async throws -> String
        let apple: Run = { calls.apple += 1; return "apple" }
        let whisper: Run = { calls.whisper += 1; throw WhisperFailed() }
        do {
            _ = try await TranscriptionEngine.whisper.transcriber(appleSpeech: apple, whisper: whisper)()
            XCTFail("expected the Whisper error")
        } catch {
            XCTAssertTrue(error is WhisperFailed)
        }
        XCTAssertEqual(calls.apple, 0)
        XCTAssertEqual(calls.whisper, 1)
        let result = try? await TranscriptionEngine.appleSpeech.transcriber(appleSpeech: apple, whisper: whisper)()
        XCTAssertEqual(result, "apple")
        XCTAssertEqual(calls.whisper, 1)
    }
}

private final class Calls: @unchecked Sendable { var apple = 0; var whisper = 0 }

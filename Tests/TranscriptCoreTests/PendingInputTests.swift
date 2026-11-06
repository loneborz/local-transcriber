import XCTest
@testable import TranscriptCore

// A waiting input owns no engine: admission reads the saved preference (LTR-82).
final class PendingInputTests: XCTestCase {
    // One fixed name: removing a domain leaves its empty plist behind.
    private let suite = "TranscriptCoreTests.PendingInput"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
    }

    private func file(_ name: String) -> JobSource { .file(URL(fileURLWithPath: "/tmp/\(name)")) }
    private func input(_ name: String) -> PendingInput { PendingInput(source: file(name), recording: nil) }
    private func prefer(_ engine: TranscriptionEngine) {
        defaults.set(engine.rawValue, forKey: TranscriptionEngine.preferenceKey)
    }

    // MARK: Preference

    func testMissingOrUnknownPreferenceIsAppleSpeech() {
        XCTAssertEqual(TranscriptionEngine.preferred(in: defaults), .appleSpeech)
        for stored: Any in ["", "Whisper", "whisperKit", 1, true, ["whisper"]] {
            defaults.set(stored, forKey: TranscriptionEngine.preferenceKey)
            XCTAssertEqual(TranscriptionEngine.preferred(in: defaults), .appleSpeech, "\(stored)")
        }
    }

    func testSavedPreferenceIsRead() {
        for engine in TranscriptionEngine.allCases {
            prefer(engine)
            XCTAssertEqual(TranscriptionEngine.preferred(in: defaults), engine)
        }
    }

    // Stored values: changing any of these strands what users have saved.
    func testPreferenceKeyAndIdentifiersAreStable() {
        XCTAssertEqual(TranscriptionEngine.preferenceKey, "transcriptionEngine")
        XCTAssertEqual(TranscriptionEngine.allCases.map(\.rawValue), ["appleSpeech", "whisper"])
    }

    // MARK: Admission

    func testAdmissionReadsThePreferenceAtThatMoment() throws {
        var pending = [input("a.m4a"), input("b.m4a"), input("c.m4a")]
        let (a, b, c) = (pending[0].id, pending[1].id, pending[2].id)
        XCTAssertEqual(pending.admit(a, whisperInstalled: true, defaults: defaults)?.engine, .appleSpeech)

        // A preference change reaches inputs still waiting, not the job already made.
        prefer(.whisper)
        let second = try XCTUnwrap(pending.admit(b, whisperInstalled: true, defaults: defaults))
        XCTAssertEqual(second.engine, .whisper)

        prefer(.appleSpeech)
        XCTAssertEqual(pending.admit(c, whisperInstalled: true, defaults: defaults)?.engine, .appleSpeech)
        XCTAssertEqual(second.engine, .whisper)
        XCTAssertTrue(pending.isEmpty)
    }

    func testWhisperWithoutItsModelLeavesTheInputWaitingAndThePreferenceAlone() {
        prefer(.whisper)
        var pending = [input("a.m4a"), input("b.m4a")]
        let ids = pending.map(\.id)

        XCTAssertNil(pending.admit(ids[0], whisperInstalled: false, defaults: defaults), "must not run with Apple Speech")
        XCTAssertEqual(pending.map(\.id), ids)
        XCTAssertEqual(defaults.string(forKey: TranscriptionEngine.preferenceKey), "whisper")

        // The same input goes through once the model is installed.
        XCTAssertEqual(pending.admit(ids[0], whisperInstalled: true, defaults: defaults)?.engine, .whisper)
        XCTAssertEqual(pending.map(\.id), [ids[1]])
    }

    // Apple Speech neither needs the model nor makes admission look at it.
    func testAppleSpeechDoesNotAskAboutTheWhisperModel() {
        var asked = 0
        func installed() -> Bool { asked += 1; return false }
        var pending = [input("a.m4a"), input("b.m4a")]
        XCTAssertEqual(pending.admit(pending[0].id, whisperInstalled: installed(), defaults: defaults)?.engine, .appleSpeech)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(asked, 0)

        prefer(.whisper)
        XCTAssertNil(pending.admit(pending[0].id, whisperInstalled: installed(), defaults: defaults))
        XCTAssertEqual(asked, 1)
    }

    func testAnInputNoLongerWaitingIsNotAdmittedTwice() {
        var pending = [input("a.m4a"), input("b.m4a")]
        let first = pending[0].id
        XCTAssertNotNil(pending.admit(first, whisperInstalled: true, defaults: defaults))
        XCTAssertNil(pending.admit(first, whisperInstalled: true, defaults: defaults))
        XCTAssertEqual(pending.count, 1)
    }

    // A recording offered again after a relaunch is an ordinary input: no engine of
    // its own, the saved preference at admission, and its entry folder kept.
    func testARecordingTakesThePreferenceAndKeepsItsFolder() throws {
        prefer(.whisper)
        let folder = URL(fileURLWithPath: "/tmp/Recording 1", isDirectory: true)
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
        var pending = [PendingInput(source: file("Recording 1/Recording 1.m4a"), recording: (folder, startedAt))]

        let admitted = try XCTUnwrap(pending.admit(pending[0].id, whisperInstalled: true, defaults: defaults))
        XCTAssertEqual(admitted.engine, .whisper)
        XCTAssertEqual(admitted.input.recording?.folder, folder)
        XCTAssertEqual(admitted.input.recording?.startedAt, startedAt)
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

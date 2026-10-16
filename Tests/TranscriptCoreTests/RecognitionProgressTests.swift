import XCTest
@testable import TranscriptCore

final class RecognitionProgressTests: XCTestCase {
    func testCoverageIsPositionOverTotal() throws {
        var progress = try XCTUnwrap(RecognitionProgress(position: 0, total: 7200))
        progress.report(position: 2538, total: 7200)
        XCTAssertEqual(progress.coverage, 2538.0 / 7200.0, accuracy: 1e-9)
        XCTAssertEqual(RecognitionProgress.clock(progress.position), "00:42:18")
        XCTAssertEqual(RecognitionProgress.clock(progress.total), "02:00:00")
    }

    func testLateOrOverlappingResultsNeverMoveItBack() throws {
        var progress = try XCTUnwrap(RecognitionProgress(position: 100, total: 600))
        progress.report(position: 80, total: 600)      // a result that ends earlier
        XCTAssertEqual(progress.position, 100)
        progress.report(position: .nan, total: 600)
        progress.report(position: -5, total: 600)
        XCTAssertEqual(progress.position, 100)
        progress.report(position: 250, total: 600)
        XCTAssertEqual(progress.position, 250)
    }

    func testItNeverClaimsMoreThanTheAudioHolds() throws {
        var progress = try XCTUnwrap(RecognitionProgress(position: 0, total: 60))
        progress.report(position: 61.2, total: 60)      // a range that overshoots the end
        XCTAssertEqual(progress.coverage, 1)
        XCTAssertEqual(RecognitionProgress(position: 9_999, total: 60)?.coverage, 1)
    }

    func testNoProgressWithoutAKnownDuration() {
        XCTAssertNil(RecognitionProgress(position: 5, total: 0))
        XCTAssertNil(RecognitionProgress(position: 5, total: .infinity))
        XCTAssertNil(RecognitionProgress(position: .nan, total: 60))
        XCTAssertEqual(RecognitionProgress.clock(.nan), "--:--:--")
    }
}

import XCTest
@testable import TranscriptCore

// LTR-73: which Apple Speech locale reservations make way for a new language.
final class LocaleReservationsTests: XCTestCase {
    let full = ["ru_RU", "nl_NL", "fr_FR", "en_US", "de_DE"]

    func testNothingIsReleasedWhileThereIsRoomOrTheLocaleIsReserved() {
        XCTAssertEqual(LocaleReservations.toRelease(needed: "es-ES", reserved: ["en_US", "de_DE"], maximum: 5, recentlyUsed: []), [])
        // Already reserved, also when spelled with an underscore: repeating a language releases nothing.
        XCTAssertEqual(LocaleReservations.toRelease(needed: "en-US", reserved: full, maximum: 5, recentlyUsed: []), [])
    }

    func testASixthLanguageReleasesTheLeastRecentlyUsedOther() {
        let used = ["en-US", "de-DE", "fr-FR", "nl-NL", "ru-RU"]
        XCTAssertEqual(LocaleReservations.toRelease(needed: "es-ES", reserved: full, maximum: 5, recentlyUsed: used), ["ru_RU"])
        // A reservation this app never recorded using goes first.
        XCTAssertEqual(LocaleReservations.toRelease(needed: "es-ES", reserved: full, maximum: 5, recentlyUsed: ["ru-RU", "nl-NL", "fr-FR", "en-US"]), ["de_DE"])
    }

    func testAShrunkAllowanceReleasesEnoughButNeverTheNeededLocale() {
        let released = LocaleReservations.toRelease(needed: "es-ES", reserved: full, maximum: 3, recentlyUsed: ["en-US", "de-DE", "fr-FR", "nl-NL", "ru-RU"])
        XCTAssertEqual(released, ["ru_RU", "nl_NL", "fr_FR"])
        XCTAssertFalse(released.contains { LocaleReservations.normalized($0) == "es-es" })
    }

    func testReturningToALanguageMovesItToTheFront() {
        let used = LocaleReservations.used("ru-RU", in: ["es-ES", "en-US", "ru_RU", "de-DE"])
        XCTAssertEqual(used, ["ru-RU", "es-ES", "en-US", "de-DE"])
    }
}

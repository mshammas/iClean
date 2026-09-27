import XCTest
@testable import iClean

/// Formatting is user-facing plain-language copy for an audience that skews elderly, so the
/// pluralization and duration edges are worth pinning down. Grouping separators are
/// locale-dependent, so those assertions stay locale-agnostic.
final class ICFormatTests: XCTestCase {

    func testItemsPluralization() {
        XCTAssertEqual(ICFormat.items(1), "1 item")
        XCTAssertEqual(ICFormat.items(0), "0 items")
        XCTAssertEqual(ICFormat.items(2), "2 items")
    }

    func testItemsSingularIsNotPlural() {
        // Regression guard for the "1 items" bug.
        XCTAssertNotEqual(ICFormat.items(1), "1 items")
    }

    func testItemsLargeCountKeepsPluralNoun() {
        let s = ICFormat.items(1234)
        XCTAssertTrue(s.hasSuffix(" items"))
        XCTAssertTrue(s.contains("1"))
    }

    func testDurationFormatting() {
        XCTAssertEqual(ICFormat.duration(0), "0:00")
        XCTAssertEqual(ICFormat.duration(5), "0:05")
        XCTAssertEqual(ICFormat.duration(65), "1:05")
        XCTAssertEqual(ICFormat.duration(3599), "59:59")
    }

    func testDurationRoundsToNearestSecond() {
        XCTAssertEqual(ICFormat.duration(65.4), "1:05")
        XCTAssertEqual(ICFormat.duration(65.6), "1:06")
    }

    func testFileSizeIsNonEmpty() {
        XCTAssertFalse(ICFormat.fileSize(0).isEmpty)
        XCTAssertFalse(ICFormat.fileSize(6_400_000_000).isEmpty)
    }

    func testCountSingleDigitHasNoSeparator() {
        XCTAssertEqual(ICFormat.count(7), "7")
    }
}

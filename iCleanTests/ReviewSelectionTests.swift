import XCTest
@testable import iClean

/// The selection set is what the delete action reads, and its central promise is that an
/// asset flagged by two detectors is counted — and deleted — exactly once.
final class ReviewSelectionTests: XCTestCase {

    func testStartsEmpty() {
        let s = ReviewSelection()
        XCTAssertTrue(s.isEmpty)
        XCTAssertEqual(s.count, 0)
        XCTAssertFalse(s.isSelected("a"))
    }

    func testToggleAddsThenRemoves() {
        var s = ReviewSelection()
        s.toggle("a")
        XCTAssertTrue(s.isSelected("a"))
        XCTAssertEqual(s.count, 1)
        s.toggle("a")
        XCTAssertFalse(s.isSelected("a"))
        XCTAssertTrue(s.isEmpty)
    }

    func testSameIDCountedOnce() {
        // An asset in two categories shares one localIdentifier — it must not double-count.
        var s = ReviewSelection()
        s.setSelected(["a"], to: true)
        s.setSelected(["a"], to: true)
        XCTAssertEqual(s.count, 1)
    }

    func testSetSelectedUnionsAndSubtracts() {
        var s = ReviewSelection()
        s.setSelected(["a", "b", "c"], to: true)
        XCTAssertEqual(s.count, 3)
        s.setSelected(["b"], to: false)
        XCTAssertFalse(s.isSelected("b"))
        XCTAssertEqual(s.count, 2)
    }

    func testDeselectingUnselectedIsHarmless() {
        var s = ReviewSelection()
        s.setSelected(["x"], to: false)
        XCTAssertTrue(s.isEmpty)
    }

    func testRemoveAll() {
        var s = ReviewSelection(selectedIDs: ["a", "b"])
        s.removeAll()
        XCTAssertTrue(s.isEmpty)
    }

    func testEqualityByContents() {
        XCTAssertEqual(ReviewSelection(selectedIDs: ["a", "b"]),
                       ReviewSelection(selectedIDs: ["b", "a"]))
        XCTAssertNotEqual(ReviewSelection(selectedIDs: ["a"]),
                          ReviewSelection(selectedIDs: ["a", "b"]))
    }
}

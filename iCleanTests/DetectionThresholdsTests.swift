import XCTest
import Vision
@testable import iClean

/// These aren't testing behaviour so much as guarding invariants between the tuned constants.
/// The calibration lives in CLAUDE.md; the point here is that a future careless edit can't
/// silently break a safety relationship (e.g. make pre-ticking looser than grouping) and
/// still compile.
final class DetectionThresholdsTests: XCTestCase {

    func testAutoTickIsStricterThanGrouping() {
        // The whole safety story: only *near-certain* copies are pre-ticked, and everything
        // pre-ticked is necessarily also grouped. If this flips, the app would pre-tick photos
        // it isn't sure are duplicates.
        XCTAssertLessThanOrEqual(DetectionThresholds.duplicateAutoTickMaxDistance,
                                 DetectionThresholds.duplicateMaxDistance)
    }

    func testDistanceThresholdsArePositive() {
        XCTAssertGreaterThan(DetectionThresholds.duplicateAutoTickMaxDistance, 0)
        XCTAssertGreaterThan(DetectionThresholds.duplicateMaxDistance, 0)
    }

    func testVeryBlurryIsSubsetOfBlurry() {
        // "Very blurry" must be a stricter cut than "blurry", or the severity wording lies.
        XCTAssertLessThanOrEqual(DetectionThresholds.veryBlurryVariance,
                                 DetectionThresholds.blurVariance)
        XCTAssertGreaterThan(DetectionThresholds.blurVariance, 0)
    }

    func testVisionRevisionIsPinnedToTwo() {
        // Every duplicate threshold was calibrated on revision 2. Revision 1 puts distances on
        // a ~74x-larger scale, so a silent downgrade would make grouping match almost nothing.
        XCTAssertEqual(DetectionThresholds.visionFeaturePrintRevision,
                       VNGenerateImageFeaturePrintRequestRevision2)
    }

    func testPreFiltersAndBudgetsArePositive() {
        XCTAssertGreaterThan(DetectionThresholds.duplicateTimeWindow, 0)
        XCTAssertGreaterThanOrEqual(DetectionThresholds.duplicateAspectTolerance, 0)
        XCTAssertGreaterThan(DetectionThresholds.duplicateMaxNeighbourComparisons, 0)
        XCTAssertGreaterThan(DetectionThresholds.duplicateMaxConcurrent, 0)
        XCTAssertGreaterThan(DetectionThresholds.blurMaxConcurrent, 0)
    }

    func testAnalysisDimensionsArePositive() {
        XCTAssertGreaterThan(DetectionThresholds.blurAnalysisDimension, 0)
        XCTAssertGreaterThan(DetectionThresholds.duplicateAnalysisDimension, 0)
        XCTAssertGreaterThan(DetectionThresholds.blurTileSize, 0)
    }

    func testLargeVideoThresholdsArePositive() {
        XCTAssertGreaterThan(DetectionThresholds.largeVideoMinBytes, 0)
        XCTAssertGreaterThan(DetectionThresholds.largeVideoMinDuration, 0)
    }
}

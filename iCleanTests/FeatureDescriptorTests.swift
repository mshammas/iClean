import XCTest
@testable import iClean

/// The distance math here decides which photos get pre-ticked for deletion, and the
/// half-precision encoding is what the on-disk cache stores. Both are load-bearing for a
/// destructive feature, so they get direct coverage.
final class FeatureDescriptorTests: XCTestCase {

    func testDistanceToSelfIsZero() throws {
        let d = FeatureDescriptor(values: [0.1, -0.4, 2.0, 0.0])
        let dist = try XCTUnwrap(d.distance(to: d))
        XCTAssertEqual(dist, 0, accuracy: 1e-6)
    }

    func testDistanceIsEuclidean() throws {
        // (0,0) to (3,4) is the classic 3-4-5 triangle.
        let a = FeatureDescriptor(values: [0, 0])
        let b = FeatureDescriptor(values: [3, 4])
        let dist = try XCTUnwrap(a.distance(to: b))
        XCTAssertEqual(dist, 5, accuracy: 1e-5)
    }

    func testDistanceIsSymmetric() throws {
        let a = FeatureDescriptor(values: [1, 2, 3])
        let b = FeatureDescriptor(values: [-1, 0, 5])
        let ab = try XCTUnwrap(a.distance(to: b))
        let ba = try XCTUnwrap(b.distance(to: a))
        XCTAssertEqual(ab, ba)
    }

    func testMismatchedLengthsReturnNilNotZero() {
        // A mismatch means different Vision revisions; it must never read as "very similar".
        let a = FeatureDescriptor(values: [1, 2, 3])
        let b = FeatureDescriptor(values: [1, 2])
        XCTAssertNil(a.distance(to: b))
    }

    func testEmptyDescriptorDistanceIsNil() {
        let empty = FeatureDescriptor(values: [])
        XCTAssertNil(empty.distance(to: empty))
    }

    func testHalfPrecisionRoundTripPreservesRepresentableValues() throws {
        // All exactly representable in Float16, matching what Vision actually produces.
        let values: [Float] = [0.0, 0.5, -0.25, 1.0, 2.0, -4.0, 0.125]
        let original = FeatureDescriptor(values: values)
        let restored = try XCTUnwrap(FeatureDescriptor(halfPrecisionData: original.halfPrecisionData))
        XCTAssertEqual(restored, original)
    }

    func testHalfPrecisionRoundTripPreservesDistances() throws {
        let a = FeatureDescriptor(values: [0.5, 0.25, -1.0, 2.0])
        let b = FeatureDescriptor(values: [0.25, -0.5, 1.0, 0.0])
        let direct = try XCTUnwrap(a.distance(to: b))

        let a2 = try XCTUnwrap(FeatureDescriptor(halfPrecisionData: a.halfPrecisionData))
        let b2 = try XCTUnwrap(FeatureDescriptor(halfPrecisionData: b.halfPrecisionData))
        let roundTripped = try XCTUnwrap(a2.distance(to: b2))

        XCTAssertEqual(direct, roundTripped)
    }

    func testHalfPrecisionRejectsGarbageLength() {
        // 3 bytes is not a whole number of Float16 values.
        XCTAssertNil(FeatureDescriptor(halfPrecisionData: Data([0x00, 0x01, 0x02])))
    }
}

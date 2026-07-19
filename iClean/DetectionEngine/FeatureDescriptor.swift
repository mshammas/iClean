import Accelerate
import Vision

/// A Vision image feature print, held as plain floats.
///
/// **Why not just keep the `VNFeaturePrintObservation`?** Because an observation cannot be
/// rebuilt from bytes — Vision exposes `data` read-only and provides no initialiser — so
/// anything we want to persist (the on-disk scan cache) or hold cheaply has to be the raw
/// descriptor. Extracting it once, at fingerprint time, also keeps a Vision object out of the
/// comparison hot loop.
///
/// `distance(to:)` reproduces `VNFeaturePrintObservation.computeDistance` **exactly**: that
/// call is plain Euclidean (L2) distance over the descriptor. Verified against Vision's own
/// implementation across multiple image pairs, matching to six decimal places. This matters
/// because `DetectionThresholds.duplicateMaxDistance` and `duplicateAutoTickMaxDistance` were
/// calibrated with Vision's version — if the metric here drifted, those numbers would quietly
/// stop meaning what they were measured to mean.
struct FeatureDescriptor: Sendable, Equatable {

    /// The descriptor itself. 768 elements at `visionFeaturePrintRevision` 2.
    let values: [Float]

    init(values: [Float]) {
        self.values = values
    }

    /// Copies the descriptor out of a Vision observation.
    ///
    /// Returns `nil` for an unexpected element type: the observation's bytes are only safe to
    /// read as `Float` when Vision says that is what they are.
    init?(_ observation: VNFeaturePrintObservation) {
        guard observation.elementType == .float,
              observation.elementCount > 0 else { return nil }

        let count = observation.elementCount
        self.values = observation.data.withUnsafeBytes { raw -> [Float] in
            guard let base = raw.baseAddress else { return [] }
            return Array(UnsafeBufferPointer(start: base.assumingMemoryBound(to: Float.self),
                                             count: count))
        }
        guard !values.isEmpty else { return nil }
    }

    /// Euclidean distance to another descriptor, or `nil` if the two aren't comparable.
    ///
    /// Mismatched lengths mean the descriptors came from different Vision revisions, whose
    /// distances live on entirely different scales (revision 1 puts a near-duplicate around
    /// 0.85 where revision 2 puts it around 0.01). Vision itself throws in that case; we
    /// return `nil` for the same reason, so a mismatch can never be read as "very similar".
    func distance(to other: FeatureDescriptor) -> Float? {
        guard values.count == other.values.count, !values.isEmpty else { return nil }
        return vDSP.distanceSquared(values, other.values).squareRoot()
    }
}

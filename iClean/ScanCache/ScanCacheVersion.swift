import Foundation

/// What makes a cached measurement stale.
///
/// The cache stores **measurements, not verdicts** — a blur score, not "is blurry"; a feature
/// print, not "is a duplicate". So what invalidates an entry is a change in *how the number was
/// produced*, never a change in how it's interpreted. Moving `blurVariance` or
/// `duplicateAutoTickMaxDistance` re-classifies from cache in milliseconds; changing the
/// analysis dimension or the Vision revision means the stored numbers no longer mean the same
/// thing and must be recomputed.
///
/// That split is deliberate and worth preserving: threshold tuning is an ongoing activity on
/// this project (`blurVariance` already moved 25 → 100, and the 0.05 auto-tick question is
/// still open), and it should never cost a four-minute re-scan.
///
/// Each table carries its own stamp, so a blur change doesn't throw away descriptors.
enum ScanCacheVersion {

    /// Bumped by hand when the *storage layout* changes, independent of the parameters below.
    private static let schema = 1

    /// Everything that determines a blur score. Note `blurVariance` is deliberately absent —
    /// it decides what the score *means*, not what it is.
    static var blur: String {
        [
            "schema=\(schema)",
            "dim=\(DetectionThresholds.blurAnalysisDimension)",
            "tile=\(DetectionThresholds.blurTileSize)",
            "pct=\(DetectionThresholds.blurTilePercentile)",
        ].joined(separator: "|")
    }

    /// Everything that determines a feature print. `duplicateMaxDistance` and
    /// `duplicateAutoTickMaxDistance` are deliberately absent, for the same reason.
    ///
    /// `rev` matters most: descriptors from different Vision revisions are not comparable at
    /// all — different lengths, distance scales ~74× apart — so a revision change must wipe
    /// every stored descriptor rather than mix old and new.
    static var descriptor: String {
        [
            "schema=\(schema)",
            "dim=\(DetectionThresholds.duplicateAnalysisDimension)",
            "rev=\(DetectionThresholds.visionFeaturePrintRevision)",
            "fmt=fp16",
        ].joined(separator: "|")
    }
}

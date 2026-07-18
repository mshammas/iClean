import Foundation

/// All tunable detection constants live here so they're easy to find and adjust after
/// testing against real libraries. Thresholds lean **conservative**: we would much rather
/// miss some clutter than suggest deleting something the user wanted.
enum DetectionThresholds {

    // MARK: Large videos

    /// Videos at or above this size are flagged. 100 MB is roughly 1–2 minutes of 4K.
    static let largeVideoMinBytes: Int64 = 100 * 1024 * 1024

    /// …or videos at least this long, regardless of size.
    static let largeVideoMinDuration: TimeInterval = 5 * 60

    /// Screen recordings are always flagged — they're rarely worth keeping long-term.
    static let alwaysFlagScreenRecordings = true

    // MARK: Blur

    /// Longest side (px) the image is resized to before measuring sharpness. Fixed so a
    /// single threshold means the same thing for every photo.
    ///
    /// **800 was chosen by measurement, not guesswork.** Downscaling removes blur, so too
    /// small a dimension makes blurry photos look sharp. Blurring a 3840×2160 photo at full
    /// resolution and then scoring it gave this sharp-vs-blurred separation:
    ///
    ///     dimension   sharp   blur r8   separation
    ///       400        551       81        6.8x
    ///       800        404        8       48.5x     ← chosen
    ///      1200        363        3      129.4x
    ///      1600        268        2      150.4x
    ///
    /// 400px barely separates them; 800px separates cleanly at a fraction of the decode
    /// cost of 1200/1600, which matters when every photo in the library is analysed.
    static let blurAnalysisDimension = 800

    /// Size (px) of each tile the sharpness score is computed over. See `SharpnessAnalyzer`
    /// for why scoring is per-tile rather than per-image.
    static let blurTileSize = 128

    /// Which percentile of tile scores represents the photo — "how sharp is the sharpest
    /// meaningful region?". Not the maximum, so one noisy speck can't rescue a blurry photo.
    static let blurTilePercentile = 0.9

    /// Tile score at or below this counts as blurry (measured at the dimension above).
    ///
    /// **Calibrated against a real 17k-photo library**, which corrected an earlier value of
    /// 25 derived from synthetic Gaussian blur. Real out-of-focus and motion-blurred photos
    /// score much higher than synthetic blur, because sensor noise and compression artefacts
    /// keep some high-frequency detail alive. Measured distribution over 4,177 real photos:
    ///
    ///     score ≤    photos   share
    ///        10          3     0.1%
    ///        25         12     0.3%   ← old threshold: only 12 hits in 17k items
    ///        50         51     1.2%
    ///       100        153     3.7%   ← chosen
    ///       200        320     7.7%
    ///       400        647    15.5%
    ///     median 1388 · min 1 · max 19444
    ///
    /// 100 flags ~3.7% of photos, a believable share of genuinely blurry shots, while
    /// staying an order of magnitude below the median (1388) so ordinary photos are safe.
    ///
    /// ⚠️ **Known false-positive mode:** a correctly-focused photo with almost no detail
    /// anywhere (blank wall, very dark shot) genuinely has few edges. Tiling greatly reduces
    /// this, and blurry items are never pre-ticked. Results are sorted blurriest-first, so
    /// the debatable calls sit at the *end* of the list — that's where to check when tuning.
    static let blurVariance: Float = 100

    /// Below this we describe it as "very blurry" rather than just "blurry".
    static let veryBlurryVariance: Float = 25

    /// How many images to analyse at once. Bounded so we don't spike memory or CPU.
    static let blurMaxConcurrent = 6

    // MARK: Duplicates

    /// Longest side (px) images are reduced to before computing a Vision feature print.
    /// Feature prints are highly scale-robust (a 50% resize moved the distance by only
    /// 0.014), so a small image is plenty and keeps the pass fast.
    static let duplicateAnalysisDimension = 256

    /// Two photos are treated as duplicates when their feature-print distance is at or
    /// below this.
    ///
    /// **Measured with `VNGenerateImageFeaturePrintRequest` on real photos:**
    ///
    ///     near-duplicates                     unrelated photos
    ///       identical            0.0000         closest pair      0.4163
    ///       re-encoded JPEG      0.0055–0.079   median            1.3149
    ///       resized 50%          0.0143         max               1.4263
    ///       cropped to 90%       0.1258
    ///       rotated 2°           0.1633
    ///       cropped to 75%       0.1874
    ///       brightness +0.25     0.4333  ← overlaps unrelated range!
    ///
    /// The ranges **overlap around 0.4**: a brightness-edited copy scores worse than the
    /// closest pair of unrelated photos. Anything near 0.4 would group different photos and
    /// pre-tick one for deletion — the worst failure this app can have. 0.15 keeps a ~2.8×
    /// margin below the unrelated minimum.
    ///
    /// The cost is recall: heavily edited copies (brightness/filters) and crops tighter than
    /// ~80% are not grouped. That is the intended trade — this is the one category that
    /// pre-ticks items, so it must only ever group near-identical copies.
    static let duplicateMaxDistance: Float = 0.15

    /// Only photos taken within this of each other are compared.
    ///
    /// Comparing every photo against every other is O(n²) and infeasible at 12,000+ photos.
    /// Duplicates overwhelmingly cluster in time (burst shots, repeated attempts at the same
    /// scene, a re-save moments later). **Known limitation:** copies created far apart — the
    /// same image saved again months later — are not found by this pass.
    static let duplicateTimeWindow: TimeInterval = 60 * 60

    /// How close two aspect ratios must be to be worth comparing at all.
    static let duplicateAspectTolerance = 0.02

    /// Extras are only **pre-ticked** when they're this close to the kept copy.
    ///
    /// Matches between this and `duplicateMaxDistance` are still shown as a group — they're
    /// almost certainly worth looking at — but they start **unticked**, so the app never
    /// proposes deleting them on its own.
    ///
    /// Measured on a real library: of 337 matches, 139 were ≤ 0.05 while 138 sat in the
    /// riskier 0.10–0.15 band. Calibration puts a re-encoded or resized copy under 0.08 but a
    /// 90%-crop at 0.126 — so the upper band is where *variations* live rather than true
    /// copies. Auto-ticking only the near-certain ones keeps the pre-tick trustworthy.
    static let duplicateAutoTickMaxDistance: Float = 0.05

    /// Hard cap on how many later photos each photo is compared against.
    ///
    /// The time window alone is not a safe bound: bulk-imported photos (from messaging apps
    /// or downloads) often share a near-identical creation date, so *thousands* can fall
    /// inside one window and the comparison becomes O(n²) — tens of millions of distance
    /// computations with the app apparently frozen. Capping bounds the work to
    /// `photos × 200` regardless of how the dates cluster. The cost is that inside a very
    /// dense burst some pairs go uncompared, which only ever *misses* duplicates.
    static let duplicateMaxNeighbourComparisons = 200

    /// Concurrent feature-print computations.
    static let duplicateMaxConcurrent = 6

    /// How often (in photos fingerprinted) to publish progress. Small, so the counter starts
    /// moving quickly — a progress bar sitting on 0 reads as a freeze.
    static let duplicateProgressInterval = 5

    // MARK: Batching

    /// How many assets to process before yielding and reporting progress.
    static let scanBatchSize = 200

    /// How often (in analysed images) to publish progress during the slower blur pass.
    static let blurProgressInterval = 20
}

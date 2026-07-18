import Foundation

/// Everything a completed scan found, grouped for the review screens.
struct ScanResults {
    let candidates: [Candidate]
    /// How many assets were examined — used for the "we checked N items" reassurance copy.
    let scannedCount: Int
    /// Photos whose sharpness we actually measured.
    let photosCheckedForBlur: Int
    /// Photos we wanted to check for blur but couldn't — almost always iCloud-only
    /// originals that aren't downloaded to this device. Surfaced to the user, because a
    /// scan that quietly skips much of the library would wrongly imply it's all clean.
    let photosUncheckedForBlur: Int
    /// Clusters of near-identical photos. The flat `candidates` list holds each group's
    /// extras; the groups carry the "keep" copy and the reasoning for the review screen.
    let duplicateGroups: [DuplicateGroup]

    init(candidates: [Candidate],
         scannedCount: Int,
         photosCheckedForBlur: Int = 0,
         photosUncheckedForBlur: Int = 0,
         duplicateGroups: [DuplicateGroup] = []) {
        self.candidates = candidates
        self.scannedCount = scannedCount
        self.photosCheckedForBlur = photosCheckedForBlur
        self.photosUncheckedForBlur = photosUncheckedForBlur
        self.duplicateGroups = duplicateGroups
    }

    static let empty = ScanResults(candidates: [], scannedCount: 0)

    /// Candidates in one category, ordered so the most useful ones come first.
    ///
    /// - **Blurry**: blurriest first. These lists can run to thousands and nobody reviews
    ///   them all, so the clearest-cut cases must be at the top — and the borderline ones,
    ///   where the threshold is doing debatable work, sit at the bottom where they're
    ///   least likely to be ticked in bulk.
    /// - **Everything else**: largest first, since those are the biggest space wins.
    func candidates(in category: CleanupCategory) -> [Candidate] {
        let matching = candidates.filter { $0.category == category }
        guard category == .blurry else {
            return matching.sorted { $0.estimatedBytes > $1.estimatedBytes }
        }
        return matching.sorted {
            ($0.detectionScore ?? .greatestFiniteMagnitude)
                < ($1.detectionScore ?? .greatestFiniteMagnitude)
        }
    }

    /// Only the categories that actually found something — we never show empty categories.
    var populatedCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { !candidates(in: $0).isEmpty }
    }

    var isEmpty: Bool { candidates.isEmpty }

    /// Total space across every suggestion (not the selected subset).
    var totalEstimatedBytes: Int64 {
        candidates.reduce(0) { $0 + $1.estimatedBytes }
    }

    /// The identifiers that should start ticked. Driven by each candidate's own `preselect`
    /// flag, so a detector can withhold a pre-tick even when its category normally grants one
    /// (favourites inside duplicate groups).
    var defaultSelectedIDs: Set<String> {
        Set(candidates.filter(\.preselect).map(\.id))
    }
}

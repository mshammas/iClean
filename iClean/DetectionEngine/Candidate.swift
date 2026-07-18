import Foundation
import Photos

/// The kinds of clutter iClean looks for. Copy here is user-facing and deliberately
/// plain-language — it appears directly on the review screens.
enum CleanupCategory: String, CaseIterable, Identifiable, Hashable {
    case duplicates
    case blurry
    case screenshots
    case largeVideos

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duplicates:  return "Duplicates"
        case .blurry:      return "Blurry Photos"
        case .screenshots: return "Screenshots"
        case .largeVideos: return "Large Videos"
        }
    }

    var iconName: String {
        switch self {
        case .duplicates:  return "rectangle.stack.badge.minus"
        case .blurry:      return "camera.filters"
        case .screenshots: return "camera.viewfinder"
        case .largeVideos: return "film"
        }
    }

    /// One-line description shown on the summary card.
    var summaryDescription: String {
        switch self {
        case .duplicates:  return "Copies of the same photo."
        case .blurry:      return "Photos that came out out-of-focus."
        case .screenshots: return "Screenshots you've taken."
        case .largeVideos: return "The videos taking up the most space."
        }
    }

    /// Longer guidance shown at the top of the review list.
    var reviewGuidance: String {
        switch self {
        case .duplicates:
            return "For each photo we've picked the best copy to keep. Exact copies are already ticked; ones that only look similar are left for you to decide. Untick anything you'd rather keep."
        case .blurry:
            return "These look out-of-focus to us, but we might be wrong. Have a look and tick only the ones you don't want."
        case .screenshots:
            return "Screenshots pile up over time. Tick the ones you no longer need."
        case .largeVideos:
            return "These are your biggest videos, so deleting one frees a lot of space. Please check each one before ticking it."
        }
    }

    /// Whether items in this category start ticked for deletion.
    ///
    /// Only duplicate *extras* are pre-ticked (keeping one copy is obviously safe).
    /// Everything else is opt-in, because deleting a photo someone wanted is the worst
    /// failure this app can have.
    var isPreselectedByDefault: Bool {
        switch self {
        case .duplicates:                            return true
        case .blurry, .screenshots, .largeVideos:    return false
        }
    }
}

/// A single item iClean suggests deleting.
struct Candidate: Identifiable {
    /// The asset's `localIdentifier` — also the identity used for selection, so an asset
    /// flagged by two detectors is only ever counted once.
    let id: String
    let asset: PHAsset
    let category: CleanupCategory
    /// Plain-language reason shown next to the thumbnail, e.g. "Screen recording · 3:42".
    let reason: String
    let estimatedBytes: Int64
    /// Set only for `.duplicates`, linking members of the same duplicate group (M4).
    let duplicateGroupID: UUID?
    /// How confident the detector is, in its own units — currently the sharpness score for
    /// blurry photos, where *lower means blurrier*. Used to show the most clear-cut
    /// suggestions first. `nil` for detectors that have no such measure.
    let detectionScore: Float?
    /// Whether this item starts ticked for deletion. Defaults to the category's rule, but a
    /// detector can override it — duplicate extras are pre-ticked *except* favourites, which
    /// are never pre-ticked no matter what.
    let preselect: Bool

    init(asset: PHAsset,
         category: CleanupCategory,
         reason: String,
         estimatedBytes: Int64,
         duplicateGroupID: UUID? = nil,
         detectionScore: Float? = nil,
         preselect: Bool? = nil) {
        self.id = asset.localIdentifier
        self.asset = asset
        self.category = category
        self.reason = reason
        self.estimatedBytes = estimatedBytes
        self.duplicateGroupID = duplicateGroupID
        self.detectionScore = detectionScore
        self.preselect = preselect ?? category.isPreselectedByDefault
    }
}

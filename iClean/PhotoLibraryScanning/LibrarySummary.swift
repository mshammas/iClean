import Foundation

/// A lightweight, `Sendable` snapshot of the user's library size. Computed off the main
/// thread and handed to the UI. Detailed per-category results come later (M2+).
struct LibrarySummary: Equatable, Sendable {
    let photoCount: Int
    let videoCount: Int

    var totalCount: Int { photoCount + videoCount }

    static let empty = LibrarySummary(photoCount: 0, videoCount: 0)
}

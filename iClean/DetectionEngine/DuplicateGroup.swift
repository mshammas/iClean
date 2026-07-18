import Foundation
import Photos

/// A cluster of near-identical photos: one we suggest keeping, and the extra copies.
///
/// This is the only place iClean proposes deletions up front (the extras start ticked), so
/// the group carries everything the review screen needs to justify that suggestion — which
/// photo is being kept, and why.
struct DuplicateGroup: Identifiable {
    let id: UUID
    /// The copy we suggest keeping. Never a deletion candidate.
    let keeper: PHAsset
    /// Plain-language reason this one was chosen, e.g. "Highest quality · a favourite".
    let keeperReason: String
    let keeperBytes: Int64
    /// The other copies, which *are* deletion candidates.
    let extras: [Candidate]

    /// Everything that could be freed by deleting the extras.
    var reclaimableBytes: Int64 {
        extras.reduce(0) { $0 + $1.estimatedBytes }
    }

    /// Total copies including the keeper.
    var totalCount: Int { extras.count + 1 }
}

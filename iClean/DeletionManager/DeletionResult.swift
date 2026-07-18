import Foundation

/// Outcome of a successful batch delete.
struct DeletionResult: Hashable {
    let deletedCount: Int
    /// Our *estimate* of the space involved. Note the space isn't reclaimed until the items
    /// leave Recently Deleted, so user-facing copy must not promise instant free space.
    let estimatedBytes: Int64
}

/// Things that can go wrong deleting. Each carries plain-language copy suitable for
/// showing directly to the user.
enum DeletionError: LocalizedError {
    /// The user declined iOS's own "Delete N items?" confirmation.
    case cancelledByUser
    case nothingToDelete
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cancelledByUser:
            return "Nothing was deleted."
        case .nothingToDelete:
            return "There was nothing to delete."
        case .failed(let message):
            return "Your photos couldn't be deleted. \(message)"
        }
    }
}

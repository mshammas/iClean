import Foundation
import Photos

/// Performs the one destructive operation in the app: moving the chosen assets to the
/// system's Recently Deleted album.
///
/// Safety notes:
/// - Assets are **re-fetched by identifier immediately before deleting**, so a long gap
///   between scanning and confirming can't leave us holding stale references.
/// - `deleteAssets` is a single change block, so the batch applies as one unit.
/// - iOS shows its *own* confirmation alert on top of ours. Declining it is a normal
///   outcome, not an error — we surface it as `cancelledByUser`.
/// - Deleted items stay in Recently Deleted for 30 days. That is the app's undo story;
///   we deliberately don't build our own trash.
struct DeletionManager {

    func delete(localIdentifiers: [String], estimatedBytes: Int64) async throws -> DeletionResult {
        guard !localIdentifiers.isEmpty else { throw DeletionError.nothingToDelete }

        // Re-fetch fresh assets right before the delete.
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        guard !assets.isEmpty else { throw DeletionError.nothingToDelete }

        let count = assets.count

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets as NSArray)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: Self.mapped(error))
                }
            }
        }

        return DeletionResult(deletedCount: count, estimatedBytes: estimatedBytes)
    }

    /// Translates PhotoKit failures into our plain-language error cases.
    private static func mapped(_ error: Error?) -> DeletionError {
        guard let error else { return .failed("Please try again.") }

        let nsError = error as NSError
        // The user tapped "Don't Allow" on iOS's own delete confirmation.
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.userCancelled.rawValue {
            return .cancelledByUser
        }
        return .failed(nsError.localizedDescription)
    }
}

import Foundation
import Photos

/// Reads the photo library via PhotoKit. In M1 this covers counting the library and
/// grabbing a few recent assets for a preview grid. Later milestones extend it to full
/// batched enumeration feeding the detection engine.
///
/// `PHFetchResult` is lazy and backed by the Photos database, so counting is cheap even
/// for very large libraries; we still do the work off the main thread to keep the UI
/// responsive and to model the pattern the heavier scans will follow.
struct PhotoLibraryFetcher {

    /// Counts photos and videos in the (accessible) library.
    func loadSummary() async -> LibrarySummary {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let images = PHAsset.fetchAssets(with: .image, options: Self.baseOptions())
                let videos = PHAsset.fetchAssets(with: .video, options: Self.baseOptions())
                continuation.resume(returning: LibrarySummary(photoCount: images.count,
                                                              videoCount: videos.count))
            }
        }
    }

    /// The most recent `limit` assets (photos and videos), newest first — used for the
    /// Home preview grid that proves thumbnail loading works.
    func loadRecentAssets(limit: Int) async -> [PHAsset] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let options = Self.baseOptions()
                options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                options.fetchLimit = limit
                // Fetch photos and videos together (exclude audio) so the grid mirrors
                // what the app actually operates on.
                options.predicate = NSPredicate(
                    format: "mediaType == %d OR mediaType == %d",
                    PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
                )
                let result = PHAsset.fetchAssets(with: options)
                var assets: [PHAsset] = []
                assets.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in assets.append(asset) }
                continuation.resume(returning: assets)
            }
        }
    }

    /// Every photo and video, newest first, as a lazy `PHFetchResult`.
    ///
    /// Synchronous by design: the result is lazy (it does not load assets up front), and
    /// callers are already running on a background actor. The scanner walks it in batches
    /// rather than materializing it into an array.
    func fetchAllAssets() -> PHFetchResult<PHAsset> {
        let options = Self.baseOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(
            format: "mediaType == %d OR mediaType == %d",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue
        )
        return PHAsset.fetchAssets(with: options)
    }

    private static func baseOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.includeAllBurstAssets = false   // treat only the burst "pick" as a normal asset for now
        return options
    }
}

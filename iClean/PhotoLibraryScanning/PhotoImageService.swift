import UIKit
import Photos
import AVFoundation

/// Loads thumbnail images for assets via a shared `PHCachingImageManager`.
///
/// We deliberately request small, downscaled images (never full resolution) so the UI
/// stays fast and memory stays low even with thousands of assets. `isNetworkAccessAllowed`
/// is on so thumbnails for iCloud-only originals still appear — PhotoKit serves a small
/// cached representation without pulling the full original.
final class PhotoImageService {
    static let shared = PhotoImageService()

    private let manager = PHCachingImageManager()

    private init() {}

    /// Requests a thumbnail sized for a square of `side` points at the given screen scale.
    /// Returns `nil` if the image can't be produced. Uses `.highQualityFormat` so the
    /// completion fires exactly once (safe to bridge to a single continuation resume).
    func thumbnail(for asset: PHAsset, side: CGFloat, scale: CGFloat) async -> UIImage? {
        let target = CGSize(width: side * scale, height: side * scale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset,
                                 targetSize: target,
                                 contentMode: .aspectFill,
                                 options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// A large image for full-screen viewing.
    ///
    /// Bounded to `maxViewingDimension` rather than the true original: that's ample for
    /// viewing and zooming on a phone, and it keeps memory predictable for 48 MP photos.
    /// Network access is on because the user explicitly asked to see this one image — for
    /// an iCloud-only original that may mean a download, hence the loading state in the UI.
    func fullScreenImage(for asset: PHAsset) async -> UIImage? {
        let target = CGSize(width: Self.maxViewingDimension, height: Self.maxViewingDimension)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset,
                                 targetSize: target,
                                 contentMode: .aspectFit,
                                 options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// A small image for on-device analysis (blur, and later duplicate feature prints).
    ///
    /// **Network access is off by default.** Scanning touches every photo, and the users this
    /// app targets often have "Optimise iPhone Storage" on — allowing downloads by default
    /// could pull gigabytes over cellular. Photos that aren't available locally return `nil`
    /// and are skipped (and counted, so the shortfall can be reported honestly).
    ///
    /// `allowsNetworkAccess` opts into fetching iCloud-only originals. It exists because
    /// skipping them can mean missing a large share of the library — but it must only ever
    /// be enabled by an explicit, informed user choice.
    ///
    /// `.highQualityFormat` (rather than `.fastFormat`) avoids being handed a degraded
    /// placeholder, which would look blurry and cause false positives.
    func analysisImage(for asset: PHAsset,
                       maxDimension: CGFloat,
                       allowsNetworkAccess: Bool = false) async -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = allowsNetworkAccess
        options.isSynchronous = false

        return await withCheckedContinuation { continuation in
            manager.requestImage(for: asset,
                                 targetSize: CGSize(width: maxDimension, height: maxDimension),
                                 contentMode: .aspectFit,
                                 options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// A player item so a video can actually be watched before deciding to delete it.
    func playerItem(for asset: PHAsset) async -> AVPlayerItem? {
        guard asset.mediaType == .video else { return nil }

        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true

        return await withCheckedContinuation { continuation in
            manager.requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    private static let maxViewingDimension: CGFloat = 2400
}

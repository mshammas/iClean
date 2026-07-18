import Foundation
import Photos

/// Works out how much space an asset takes up.
///
/// PhotoKit has no public file-size API. `PHAssetResource` carries an undocumented
/// `fileSize` value that's reliable in practice, so we read it via KVC — but we guard
/// with `responds(to:)` first, because `value(forKey:)` on a missing key raises an
/// Objective-C exception (which would crash the app, not throw a Swift error).
/// When it isn't available we fall back to an estimate so sizes are never zero.
enum AssetResourceInfo {

    /// Best-known size in bytes for an asset. Never returns 0.
    static func estimatedFileSize(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        var largest: Int64 = 0

        for resource in resources {
            guard resource.responds(to: NSSelectorFromString("fileSize")) else { continue }
            if let number = resource.value(forKey: "fileSize") as? NSNumber {
                largest = max(largest, number.int64Value)
            }
        }

        return largest > 0 ? largest : fallbackEstimate(for: asset)
    }

    /// Rough estimate used when PhotoKit won't tell us the real size.
    private static func fallbackEstimate(for asset: PHAsset) -> Int64 {
        switch asset.mediaType {
        case .video:
            // Assume ~10 Mbps, typical for 1080p capture on iPhone.
            let bytesPerSecond: Double = 10_000_000 / 8
            return Int64(max(asset.duration, 1) * bytesPerSecond)
        default:
            // Rough HEIC/JPEG estimate at ~0.25 bytes per pixel, floored so tiny
            // images don't report an implausible size.
            let pixels = Int64(asset.pixelWidth) * Int64(asset.pixelHeight)
            return max(pixels / 4, 200_000)
        }
    }
}

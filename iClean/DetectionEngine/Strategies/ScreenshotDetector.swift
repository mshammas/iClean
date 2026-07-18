import Foundation
import Photos

/// Finds screenshots. This is metadata-only — PhotoKit already tags them — so it costs
/// nothing and runs in the first, cheap pass of a scan.
enum ScreenshotDetector {

    static func candidate(for asset: PHAsset) -> Candidate? {
        guard asset.mediaType == .image,
              asset.mediaSubtypes.contains(.photoScreenshot) else { return nil }

        let bytes = AssetResourceInfo.estimatedFileSize(for: asset)
        return Candidate(asset: asset,
                         category: .screenshots,
                         reason: "Screenshot · \(ICFormat.fileSize(bytes))",
                         estimatedBytes: bytes)
    }
}

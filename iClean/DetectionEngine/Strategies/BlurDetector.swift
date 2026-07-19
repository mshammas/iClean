import UIKit
import Photos

/// Finds out-of-focus photos by measuring sharpness on a downscaled copy.
///
/// Unlike the screenshot and large-video detectors, this needs actual pixel data, so it's
/// async and runs in the slower second pass of a scan.
///
/// Deliberately cautious:
/// - screenshots and videos are skipped (a screenshot is never "blurry" in a useful sense)
/// - **Portrait-mode photos are skipped entirely** — their blurred background is the whole
///   point of the shot, so flagging one would be plainly wrong. `SharpnessAnalyzer`'s
///   per-tile scoring already handles them well, but a photo the user deliberately composed
///   for blur deserves a guarantee rather than a comfortable margin.
/// - photos that aren't downloaded locally are skipped rather than pulled from iCloud
/// - the threshold only catches clearly-blurry photos, and nothing is pre-ticked
enum BlurDetector {

    /// What happened when we tried to judge one photo. We distinguish "checked and it's
    /// fine" from "couldn't check it", because a scan that silently skips most of the
    /// library would wrongly imply the library is clean.
    enum Outcome {
        case blurry(Candidate)
        /// Judged acceptable. Carries the score so we can see the distribution and tune the
        /// threshold from real data rather than guesswork.
        case sharp(Float)
        /// Not a candidate for blur analysis at all (video, screenshot, Portrait shot).
        case notEligible
        /// PhotoKit gave us no usable image — an iCloud-only original that isn't downloaded
        /// here, or a file that failed to decode.
        case couldNotLoad
        /// An image arrived, but far smaller than requested (typically a cached thumbnail
        /// of a large photo), so scoring it would not be comparable. Tracked separately
        /// because this is *our* guard rejecting it, not PhotoKit failing.
        case deliveredTooSmall

        /// The measured score, or `nil` when nothing was measured.
        ///
        /// Doubles as the "is this cacheable?" test: exactly the outcomes that produced a real
        /// number are the ones worth storing. Failures deliberately return `nil` — see the
        /// caching note in `DetectionCoordinator.findBlurryPhotos`.
        var sharpnessScore: Float? {
            switch self {
            case .blurry(let candidate): return candidate.detectionScore
            case .sharp(let score):      return score
            default:                     return nil
            }
        }
    }

    /// Whether this asset is worth loading pixels for at all — metadata only, so free.
    ///
    /// Checked by the coordinator before consulting the cache: an ineligible photo has no score
    /// to cache and never will, so it should not occupy a lookup or a row.
    static func isEligible(_ asset: PHAsset) -> Bool {
        asset.mediaType == .image
            && !asset.mediaSubtypes.contains(.photoScreenshot)
            && !asset.mediaSubtypes.contains(.photoDepthEffect)
    }

    /// Classifies a photo from an already-measured sharpness score, without touching pixels.
    ///
    /// This split is what makes caching worthwhile: measuring the score means decoding an
    /// 800px image, while turning a score into a verdict is a comparison. Because only the
    /// score is stored, moving `blurVariance` re-classifies the whole library instantly
    /// instead of forcing a re-measure — see `ScanCacheVersion`.
    static func outcome(for asset: PHAsset, sharpness: Float) -> Outcome {
        guard sharpness <= DetectionThresholds.blurVariance else { return .sharp(sharpness) }

        let bytes = AssetResourceInfo.estimatedFileSize(for: asset)
        let severity = sharpness <= DetectionThresholds.veryBlurryVariance
            ? "Looks very blurry"
            : "Looks blurry"

        return .blurry(Candidate(asset: asset,
                                 category: .blurry,
                                 reason: "\(severity) · \(ICFormat.fileSize(bytes))",
                                 estimatedBytes: bytes,
                                 detectionScore: sharpness))
    }

    /// - Parameter allowsICloudDownload: when true, iCloud-only originals are fetched rather
    ///   than skipped. Only ever set from an explicit user opt-in — it can mean downloading
    ///   thousands of photos.
    static func analyse(asset: PHAsset, allowsICloudDownload: Bool = false) async -> Outcome {
        guard isEligible(asset) else { return .notEligible }

        let dimension = DetectionThresholds.blurAnalysisDimension
        guard let image = await PhotoImageService.shared.analysisImage(
            for: asset,
            maxDimension: CGFloat(dimension),
            allowsNetworkAccess: allowsICloudDownload
        ) else {
            return .couldNotLoad
        }
        guard isLargeEnoughToJudge(image, asset: asset, requested: dimension) else {
            return .deliveredTooSmall
        }
        guard let sharpness = SharpnessAnalyzer.sharpnessScore(of: image) else {
            return .couldNotLoad
        }

        return outcome(for: asset, sharpness: sharpness)
    }

    /// Guards against scoring an image that came back much smaller than we asked for.
    ///
    /// With network access off, PhotoKit may hand back a small cached thumbnail of a large
    /// photo. Sharpness scores are only comparable at a consistent size, and a shrunken
    /// copy of a sharp photo can score like a blurry one — so we skip rather than risk a
    /// false "blurry" flag. Genuinely small photos (where the asset itself is small) are
    /// still judged normally.
    private static func isLargeEnoughToJudge(_ image: UIImage,
                                             asset: PHAsset,
                                             requested: Int) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let deliveredLongestSide = max(cgImage.width, cgImage.height)
        let assetLongestSide = max(asset.pixelWidth, asset.pixelHeight)
        // The best we could hope for: the asset's own size, capped at what we requested.
        let attainable = min(assetLongestSide, requested)
        guard attainable > 0 else { return false }
        return Double(deliveredLongestSide) >= Double(attainable) * 0.6
    }
}

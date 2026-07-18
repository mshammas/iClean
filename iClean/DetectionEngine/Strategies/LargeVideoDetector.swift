import Foundation
import Photos

/// Finds videos worth reviewing because of the space they take: anything over the size or
/// duration thresholds, plus screen recordings (which are rarely worth keeping).
/// Metadata + resource size only — no pixel analysis, so this runs in the cheap first pass.
enum LargeVideoDetector {

    static func candidate(for asset: PHAsset) -> Candidate? {
        guard asset.mediaType == .video else { return nil }

        let bytes = AssetResourceInfo.estimatedFileSize(for: asset)
        let isScreenRecording = asset.mediaSubtypes.contains(.videoScreenRecording)
        let isBig = bytes >= DetectionThresholds.largeVideoMinBytes
        let isLong = asset.duration >= DetectionThresholds.largeVideoMinDuration

        let flagged = isBig || isLong
            || (isScreenRecording && DetectionThresholds.alwaysFlagScreenRecordings)
        guard flagged else { return nil }

        let sizeText = ICFormat.fileSize(bytes)
        let durationText = ICFormat.duration(asset.duration)
        let label = isScreenRecording ? "Screen recording" : "Video"

        return Candidate(asset: asset,
                         category: .largeVideos,
                         reason: "\(label) · \(durationText) · \(sizeText)",
                         estimatedBytes: bytes)
    }
}

import Foundation

/// Progress of an in-flight scan, streamed to the UI. `Sendable` so it can cross from the
/// scanning actor to the main actor safely.
struct ScanProgress: Equatable, Sendable {

    /// Scanning happens in two passes: a fast metadata sweep, then the slower
    /// look-at-the-pixels pass. Surfacing which one is running keeps the long second pass
    /// from feeling like the app has stalled.
    enum Phase: Int, Equatable, Sendable {
        case quickChecks = 1
        case sharpness = 2
        case duplicates = 3

        static let count = 3

        var description: String {
            switch self {
            case .quickChecks: return "Looking for screenshots and large videos"
            case .sharpness:   return "Checking photos for blurriness"
            case .duplicates:  return "Looking for duplicate photos"
            }
        }
    }

    var phase: Phase = .quickChecks
    var scanned: Int
    var total: Int
    /// Optional sub-step wording, for phases with more than one stage (fingerprinting vs
    /// comparing). Keeps the step count at 3 while still explaining what's happening.
    var detail: String? = nil
    /// True when the slower opt-in pass that downloads iCloud originals is running, so the
    /// UI can explain why this is taking much longer than a normal scan.
    var includesICloudPhotos: Bool = false

    var fractionComplete: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(scanned) / Double(total))
    }

    /// e.g. "Step 1 of 2 · Looking for screenshots and large videos"
    var phaseText: String {
        var base = "Step \(phase.rawValue) of \(Phase.count) · \(phase.description)"
        if let detail { base += " — \(detail)" }
        guard includesICloudPhotos, phase != .quickChecks else { return base }
        return base + ", including photos from iCloud"
    }

    /// e.g. "Checked 2,340 of 8,500"
    var statusText: String {
        "Checked \(ICFormat.count(scanned)) of \(ICFormat.count(total))"
    }

    static let zero = ScanProgress(scanned: 0, total: 0)
}

import Foundation

/// Small, centralized formatting helpers so numbers and sizes read consistently
/// (and in plain language) everywhere in the app.
enum ICFormat {
    /// A grouped integer, e.g. `8,532`.
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// A human file size, e.g. `6.2 GB`. Uses the file-size style users recognize
    /// from the Settings > Storage screens.
    static func fileSize(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// A short duration like `1:05` or `3:42` for videos.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

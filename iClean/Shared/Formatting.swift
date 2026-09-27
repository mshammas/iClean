import Foundation

/// Small, centralized formatting helpers so numbers and sizes read consistently
/// (and in plain language) everywhere in the app.
enum ICFormat {
    /// A grouped integer, e.g. `8,532`.
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// A grouped count with the word "item" pluralized to match, e.g. `1 item`, `8,532 items`.
    /// Use this rather than hand-writing `"\(count(n)) items"`, which reads "1 items" at one.
    static func items(_ value: Int) -> String {
        "\(count(value)) \(value == 1 ? "item" : "items")"
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

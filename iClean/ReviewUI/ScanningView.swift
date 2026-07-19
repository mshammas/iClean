import SwiftUI

/// Shown while a scan is running. Plain-language status, a clear progress bar, and an
/// obvious way out — scanning should never feel like being trapped.
struct ScanningView: View {
    let progress: ScanProgress
    let onCancel: () -> Void

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .icIconSize(56)
                    .foregroundStyle(ICColor.primary)
                    .accessibilityHidden(true)

                Text("Checking your photos…")
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)

                Text("This can take a little while for a big library. You can stop at any time.")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ProgressView(value: progress.fractionComplete)
                    .tint(ICColor.primary)
                    .scaleEffect(x: 1, y: 2.5, anchor: .center)
                    .padding(.vertical, 8)

                Text(progress.statusText)
                    .icStyle(.bodyBold)
                    .foregroundStyle(ICColor.primaryText)

                Text(progress.phaseText)
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Scanning. \(progress.phaseText). \(progress.statusText)")

            Text("Nothing is deleted while we look. You'll get to review everything first.")
                .icStyle(.caption)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            ICButton(title: "Stop", systemImage: "xmark", role: .secondary, action: onCancel)
        }
    }
}

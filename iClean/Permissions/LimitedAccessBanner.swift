import SwiftUI

/// A dismissible banner shown on Home when the user granted only *limited* photo access.
/// Explains that iClean can only see the chosen photos, and offers to open the system
/// picker so they can add more (or grant full access).
struct LimitedAccessBanner: View {
    /// Presents the limited-library picker via `PHPhotoLibrary.presentLimitedLibraryPicker`.
    let onChooseMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .icIconSize(28)
                    .foregroundStyle(ICColor.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You've shared only some photos")
                        .icStyle(.bodyBold)
                        .foregroundStyle(ICColor.primaryText)
                    Text("iClean can only check the photos you've chosen. To clean your whole library, add more.")
                        .icStyle(.caption)
                        .foregroundStyle(ICColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ICButton(title: "Choose More Photos",
                     systemImage: "photo.badge.plus",
                     role: .secondary,
                     action: onChooseMore)
        }
        .padding(16)
        .background(ICColor.warning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

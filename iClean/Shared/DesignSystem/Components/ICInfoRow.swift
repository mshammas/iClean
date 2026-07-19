import SwiftUI

/// A single explanatory row: a large icon, a title, and a short description.
/// Used on onboarding and permission screens to explain the app in plain language.
struct ICInfoRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color = ICColor.primary

    @ScaledMetric(relativeTo: .title3) private var iconWidth: CGFloat = 44

    var body: some View {
        ICAdaptiveStack(horizontalSpacing: 16, verticalSpacing: 8, rowAlignment: .top) {
            Image(systemName: systemImage)
                .icIconSize(34)
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .icStyle(.bodyBold)
                    .foregroundStyle(ICColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Claims the remaining width when laid out as a row, and the full width once
            // stacked. A trailing Spacer would work for the row but stretch the stack.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

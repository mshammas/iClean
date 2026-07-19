import SwiftUI

/// One reviewable item: thumbnail, plain-language reason, and a big tick box.
///
/// Two separate tap targets, so neither is a surprise:
/// - the **thumbnail** opens a full-screen view (with a magnifier badge so it's discoverable)
/// - the **rest of the row** ticks/unticks the item
struct CandidateRow: View {
    let candidate: Candidate
    let isSelected: Bool
    let onToggle: () -> Void
    let onViewFullScreen: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The thumbnail grows with the text. Someone who has turned type up is usually telling
    /// us they can't see small things — a 64pt thumbnail beside 50pt text is no use to them.
    @ScaledMetric(relativeTo: .title3) private var thumbSide: CGFloat = 64

    var body: some View {
        ICAdaptiveStack(horizontalSpacing: 16, verticalSpacing: 12, rowAlignment: .center) {
            Button(action: onViewFullScreen) {
                AssetThumbnailView(asset: candidate.asset, side: thumbSide)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "magnifyingglass")
                            .icIconSize(12, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(3)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View full screen")
            .accessibilityHint("Shows this item large so you can see it clearly")
            .accessibilityAddTraits(.isButton)

            Button(action: onToggle) {
                ICAdaptiveStack(horizontalSpacing: 16, verticalSpacing: 8, rowAlignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.reason)
                            .icStyle(.bodyBold)
                            .foregroundStyle(ICColor.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(isSelected ? "Will be deleted" : "Will be kept")
                            .icStyle(.caption)
                            .foregroundStyle(isSelected ? ICColor.destructive : ICColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .icIconSize(32)
                        .foregroundStyle(isSelected ? ICColor.destructive : ICColor.secondaryText)
                        // Once stacked the tick sits under the text, so give it the same
                        // full-width tap area rather than a lone symbol in the corner.
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                               alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(candidate.reason)
            .accessibilityValue(isSelected ? "Ticked for deletion" : "Not ticked")
            .accessibilityHint("Double tap to change")
            .accessibilityAddTraits(.isButton)
        }
        .padding(.vertical, 10)
    }
}

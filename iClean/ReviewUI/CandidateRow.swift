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

    var body: some View {
        HStack(spacing: 16) {
            Button(action: onViewFullScreen) {
                AssetThumbnailView(asset: candidate.asset, side: 64)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
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
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.reason)
                            .icStyle(.bodyBold)
                            .foregroundStyle(ICColor.primaryText)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(isSelected ? "Will be deleted" : "Will be kept")
                            .icStyle(.caption)
                            .foregroundStyle(isSelected ? ICColor.destructive : ICColor.secondaryText)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 32))
                        .foregroundStyle(isSelected ? ICColor.destructive : ICColor.secondaryText)
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

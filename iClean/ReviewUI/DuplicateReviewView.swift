import SwiftUI

/// Review screen for duplicates.
///
/// Different from the other categories in one important way: these items start **ticked**.
/// So the screen leads with what's being *kept*, not what's being deleted — each group shows
/// the keeper first, clearly marked and visibly not deletable, with the extra copies beneath.
/// The aim is that "one copy of this is definitely staying" is obvious at a glance.
struct DuplicateReviewView: View {
    @ObservedObject var viewModel: CleanupViewModel

    @State private var viewingCandidate: Candidate?

    private var groups: [DuplicateGroup] { viewModel.duplicateGroups }

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 8) {
                Text(CleanupCategory.duplicates.title)
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)
                Text(CleanupCategory.duplicates.reviewGuidance)
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVStack(spacing: 20) {
                ForEach(groups) { group in
                    groupCard(group)
                }
            }
        } footer: {
            let ticked = viewModel.selection.selectedCount(in: viewModel.candidates(in: .duplicates))
            Text(ticked == 0
                 ? "Nothing ticked in Duplicates"
                 : "\(ICFormat.count(ticked)) extra copies ticked")
                .icStyle(.bodyBold)
                .foregroundStyle(ticked == 0 ? ICColor.secondaryText : ICColor.primaryText)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(CleanupCategory.duplicates.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewingCandidate) { candidate in
            FullScreenAssetView(candidate: candidate, viewModel: viewModel)
        }
    }

    // MARK: Group card

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(ICFormat.count(group.totalCount)) copies of the same photo")
                .icStyle(.sectionTitle)
                .foregroundStyle(ICColor.primaryText)

            keeperRow(group)

            Divider()

            ForEach(group.extras) { extra in
                CandidateRow(candidate: extra,
                             isSelected: viewModel.selection.isSelected(extra.id),
                             onToggle: { viewModel.toggle(extra) },
                             onViewFullScreen: { viewingCandidate = extra })
            }
        }
        .padding(16)
        .background(ICColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// The copy being kept. Deliberately has no tick box — it is not deletable from here,
    /// which is the reassurance that matters most on this screen.
    private func keeperRow(_ group: DuplicateGroup) -> some View {
        HStack(spacing: 16) {
            AssetThumbnailView(asset: group.keeper, side: 64)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(ICColor.success)
                        .background(Circle().fill(.white).padding(1))
                        .padding(3)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(group.keeperReason)
                    .icStyle(.bodyBold)
                    .foregroundStyle(ICColor.success)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ICFormat.fileSize(group.keeperBytes))
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.keeperReason). \(ICFormat.fileSize(group.keeperBytes)). This one will not be deleted.")
    }
}

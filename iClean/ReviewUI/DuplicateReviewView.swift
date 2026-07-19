import SwiftUI

/// Review screen for duplicates.
///
/// Different from the other categories in one important way: these items start **ticked**.
/// So the screen leads with what's being *kept*, not what's being deleted — each group shows
/// the keeper first, clearly marked and visibly not deletable, with the extra copies beneath.
/// The aim is that "one copy of this is definitely staying" is obvious at a glance.
struct DuplicateReviewView: View {
    @ObservedObject var viewModel: CleanupViewModel

    @State private var viewingSelection: FullScreenSelection?
    /// The group awaiting confirmation for an immediate delete.
    @State private var groupPendingDeletion: DuplicateGroup?

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

            if groups.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(ICColor.success)
                        .accessibilityHidden(true)
                    Text("You've been through all the duplicates. One copy of each photo has been kept.")
                        .icStyle(.body)
                        .foregroundStyle(ICColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                LazyVStack(spacing: 20) {
                    ForEach(groups) { group in
                        groupCard(group)
                    }
                }
            }
        } footer: {
            let ticked = viewModel.selection.selectedCount(in: groups.flatMap(\.extras))
            Text(ticked == 0
                 ? "Nothing ticked in Duplicates"
                 : "\(ICFormat.count(ticked)) extra copies ticked")
                .icStyle(.bodyBold)
                .foregroundStyle(ticked == 0 ? ICColor.secondaryText : ICColor.primaryText)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(CleanupCategory.duplicates.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewingSelection) { selection in
            FullScreenAssetView(selection: selection, viewModel: viewModel)
        }
        .alert("Delete these copies?",
               isPresented: Binding(get: { groupPendingDeletion != nil },
                                    set: { if !$0 { groupPendingDeletion = nil } }),
               presenting: groupPendingDeletion) { group in
            Button("Cancel", role: .cancel) { groupPendingDeletion = nil }
            Button("Delete", role: .destructive) {
                groupPendingDeletion = nil
                Task { _ = await viewModel.deleteTicked(in: group) }
            }
        } message: { group in
            let ticked = tickedExtras(in: group)
            let bytes = ticked.reduce(Int64(0)) { $0 + $1.estimatedBytes }
            Text("\(ICFormat.count(ticked.count)) copies will move to Recently Deleted, freeing about \(ICFormat.fileSize(bytes)). You can get them back from the Photos app for 30 days.\n\nThe copy marked as kept stays on your iPhone.")
        }
    }

    /// Opens the viewer on the whole group — keeper first, then its copies — so the user can
    /// swipe between them and judge the deletion by direct comparison. The viewer rebuilds
    /// its pages from the group, so changing which copy is kept updates it in place.
    private func present(_ group: DuplicateGroup, startingAt id: String) {
        viewingSelection = FullScreenSelection(groupID: group.id, startID: id)
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
                             onViewFullScreen: { present(group, startingAt: extra.id) })
            }

            // Deal with a group as soon as it's been judged, rather than carrying every
            // decision to the end of a long review.
            let ticked = tickedExtras(in: group)
            if !ticked.isEmpty {
                ICButton(title: "Delete \(ICFormat.count(ticked.count)) now",
                         systemImage: "trash",
                         role: .destructive,
                         isEnabled: !viewModel.isDeleting) {
                    groupPendingDeletion = group
                }
            }
        }
        .padding(16)
        .background(ICColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func tickedExtras(in group: DuplicateGroup) -> [Candidate] {
        group.extras.filter { viewModel.selection.isSelected($0.id) }
    }

    /// The copy being kept. Deliberately has no tick box — it is not deletable from here,
    /// which is the reassurance that matters most on this screen. It *is* tappable though:
    /// checking a group really is duplicates means looking at the copy being kept, not just
    /// the ones being deleted.
    private func keeperRow(_ group: DuplicateGroup) -> some View {
        Button {
            present(group, startingAt: group.keeper.localIdentifier)
        } label: {
            HStack(spacing: 16) {
                AssetThumbnailView(asset: group.keeper, side: 64)
                    .overlay(alignment: .topLeading) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.55), in: Circle())
                            .padding(3)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Label(group.keeperReason, systemImage: "checkmark.seal.fill")
                        .icStyle(.bodyBold)
                        .foregroundStyle(ICColor.success)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ICFormat.fileSize(group.keeperBytes))
                        .icStyle(.caption)
                        .foregroundStyle(ICColor.secondaryText)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.keeperReason). \(ICFormat.fileSize(group.keeperBytes)). This one will not be deleted.")
        .accessibilityHint("Double tap to see it full screen")
        .accessibilityAddTraits(.isButton)
    }
}

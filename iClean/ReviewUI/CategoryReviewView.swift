import SwiftUI

/// The review checklist for one category. Nothing here deletes anything — it only changes
/// what's ticked. The actual delete happens once, later, from the summary screen.
struct CategoryReviewView: View {
    let category: CleanupCategory
    @ObservedObject var viewModel: CleanupViewModel

    /// The item being viewed full screen, if any.
    @State private var viewingSelection: FullScreenSelection?

    private var candidates: [Candidate] { viewModel.candidates(in: category) }
    private var allSelected: Bool { viewModel.selection.allSelected(in: candidates) }
    private var selectedCount: Int { viewModel.selection.selectedCount(in: candidates) }

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 8) {
                Text(category.title)
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)
                Text(category.reviewGuidance)
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ICButton(title: allSelected ? "Untick All" : "Tick All",
                     systemImage: allSelected ? "circle" : "checkmark.circle",
                     role: .secondary) {
                viewModel.setAll(in: category, selected: !allSelected)
            }

            // LazyVStack, not VStack: a category can hold thousands of items, and an eager
            // stack would build every row — and fire every thumbnail request — at once,
            // swamping PhotoKit's decoder. Lazily built rows only load what's on screen.
            LazyVStack(spacing: 0) {
                ForEach(candidates) { candidate in
                    CandidateRow(candidate: candidate,
                                 isSelected: viewModel.selection.isSelected(candidate.id),
                                 onToggle: { viewModel.toggle(candidate) },
                                 onViewFullScreen: {
                                     viewingSelection = FullScreenSelection(
                                         single: FullScreenTarget(candidate: candidate))
                                 })
                    if candidate.id != candidates.last?.id {
                        Divider()
                    }
                }
            }
        } footer: {
            Text(selectedCount == 0
                 ? "Nothing ticked in \(category.title)"
                 : "\(ICFormat.count(selectedCount)) ticked in \(category.title)")
                .icStyle(.bodyBold)
                .foregroundStyle(selectedCount == 0 ? ICColor.secondaryText : ICColor.primaryText)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $viewingSelection) { selection in
            FullScreenAssetView(selection: selection, viewModel: viewModel)
        }
    }
}

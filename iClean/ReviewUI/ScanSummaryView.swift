import SwiftUI

/// What the scan found, as one card per category. This is the hub of the review flow:
/// drill into a category to tick items, then delete everything ticked in one go.
struct ScanSummaryView: View {
    @ObservedObject var viewModel: CleanupViewModel
    let onOpenCategory: (CleanupCategory) -> Void
    let onDelete: () -> Void
    /// Re-runs the scan with iCloud downloads enabled, after the user has agreed.
    let onCheckICloudPhotos: () -> Void

    @State private var showingICloudConfirmation = false

    private var results: ScanResults { viewModel.results ?? .empty }

    var body: some View {
        ICScreen {
            header

            if viewModel.populatedCategories.isEmpty {
                emptyState
                coverageNote
            } else {
                ForEach(viewModel.populatedCategories) { category in
                    categoryCard(category)
                }

                coverageNote

                Text("Deleted items go to your Recently Deleted album and stay there for 30 days, so you can get them back if you change your mind.")
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            if !viewModel.populatedCategories.isEmpty {
                deleteFooter
            }
        }
        .navigationTitle("What we found")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.populatedCategories.isEmpty ? "All clean!" : "Here's what we found")
                .icStyle(.screenTitle)
                .foregroundStyle(ICColor.primaryText)
            Text("We checked \(ICFormat.count(results.scannedCount)) items in your library.")
                .icStyle(.body)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown when some photos couldn't be examined for blurriness — almost always because
    /// they live in iCloud and aren't downloaded here. Saying so plainly matters: otherwise
    /// "we found nothing" reads as "your library is clean" when we simply couldn't look.
    @ViewBuilder
    private var coverageNote: some View {
        if results.photosUncheckedForBlur > 0 {
            VStack(alignment: .leading, spacing: 12) {
                ICInfoRow(systemImage: "icloud.slash",
                          title: "Some photos couldn't be checked for blur",
                          detail: "\(ICFormat.count(results.photosUncheckedForBlur)) of your photos aren't downloaded to this iPhone, so we couldn't look at them closely. We checked \(ICFormat.count(results.photosCheckedForBlur)). Everything else above was still checked.",
                          tint: ICColor.warning)

                ICButton(title: "Check Those Too",
                         systemImage: "icloud.and.arrow.down",
                         role: .secondary) {
                    showingICloudConfirmation = true
                }
            }
            .padding(16)
            .background(ICColor.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .alert("Check your iCloud photos?", isPresented: $showingICloudConfirmation) {
                Button("Not Now", role: .cancel) {}
                Button("Check Them") { onCheckICloudPhotos() }
            } message: {
                Text("iClean will download \(ICFormat.count(results.photosUncheckedForBlur)) photos from iCloud so it can check them. This uses internet data and can take a long time.\n\nPlease connect to Wi-Fi first, and keep your iPhone plugged in. You can stop at any time.")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(ICColor.success)
                .accessibilityHidden(true)
            Text("We didn't find anything worth deleting. Your library is in good shape.")
                .icStyle(.body)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func categoryCard(_ category: CleanupCategory) -> some View {
        let items = viewModel.candidates(in: category)
        let ticked = viewModel.selection.selectedCount(in: items)
        let bytes = items.reduce(Int64(0)) { $0 + $1.estimatedBytes }

        return Button {
            onOpenCategory(category)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: category.iconName)
                    .font(.system(size: 34))
                    .foregroundStyle(ICColor.primary)
                    .frame(width: 44)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(category.title)
                        .icStyle(.sectionTitle)
                        .foregroundStyle(ICColor.primaryText)
                    Text("\(ICFormat.count(items.count)) items · \(ICFormat.fileSize(bytes))")
                        .icStyle(.caption)
                        .foregroundStyle(ICColor.secondaryText)
                    Text(ticked == 0 ? "None ticked yet" : "\(ICFormat.count(ticked)) ticked")
                        .icStyle(.caption)
                        .foregroundStyle(ticked == 0 ? ICColor.secondaryText : ICColor.destructive)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ICColor.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ICColor.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.title). \(items.count) items, \(ICFormat.fileSize(bytes)). \(ticked) ticked for deletion.")
        .accessibilityHint("Double tap to review")
        .accessibilityAddTraits(.isButton)
    }

    private var deleteFooter: some View {
        VStack(spacing: 10) {
            if viewModel.selectedCount == 0 {
                Text("Tick the items you'd like to delete.")
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
                    .multilineTextAlignment(.center)
            }
            ICButton(title: viewModel.selectedCount == 0
                        ? "Nothing ticked yet"
                        : "Delete \(ICFormat.count(viewModel.selectedCount)) items",
                     systemImage: "trash",
                     role: .destructive,
                     isEnabled: viewModel.selectedCount > 0,
                     action: onDelete)
        }
    }
}

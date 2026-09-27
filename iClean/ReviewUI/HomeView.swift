import SwiftUI

/// Home screen: the size of the library, a preview grid of recent photos, and the button
/// that starts a scan. The flow around it is owned by `CleanupFlowView`.
struct HomeView: View {
    let hasLimitedAccess: Bool
    let onChooseMorePhotos: () -> Void
    /// Changes when the library may have changed (e.g. after a deletion), triggering a reload.
    let refreshToken: Int
    let onScan: () -> Void

    @StateObject private var viewModel = HomeViewModel()
    @State private var showingClearCacheConfirmation = false

    @ScaledMetric(relativeTo: .title3) private var thumbSide: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var totalCountSize: CGFloat = 56

    /// True only once the count has actually loaded — an empty library is a real state to
    /// explain, but "no photos" must not be shown while we're still counting.
    private var hasEmptyLibrary: Bool {
        (viewModel.summary?.totalCount ?? 0) == 0 && viewModel.summary != nil
    }

    var body: some View {
        ICScreen {
            if hasLimitedAccess {
                LimitedAccessBanner(onChooseMore: onChooseMorePhotos)
            }

            header

            summaryCard

            if hasEmptyLibrary {
                emptyLibraryNote
            }

            if !viewModel.recentAssets.isEmpty {
                recentPreview
            }

            if let cacheBytes = viewModel.cacheBytes {
                cacheNote(bytes: cacheBytes)
            }
        } footer: {
            ICButton(title: "Scan My Photos",
                     systemImage: "magnifyingglass",
                     isEnabled: !hasEmptyLibrary && viewModel.summary != nil,
                     action: onScan)
        }
        .task(id: refreshToken) { await viewModel.load() }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("iClean")
                .icStyle(.screenTitle)
                .foregroundStyle(ICColor.primaryText)
            Text(hasLimitedAccess
                 ? "Here are the photos and videos you've shared."
                 : "Here's what's in your photo library.")
                .icStyle(.body)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let summary = viewModel.summary {
                Text(ICFormat.count(summary.totalCount))
                    .font(.system(size: totalCountSize, weight: .bold, design: .rounded))
                    .foregroundStyle(ICColor.primaryText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .accessibilityLabel("\(ICFormat.items(summary.totalCount)) in your library")
                Text("items in total")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)

                Divider()

                ICAdaptiveStack(horizontalSpacing: 24, verticalSpacing: 12) {
                    statItem(count: summary.photoCount, label: "Photos", systemImage: "photo")
                    statItem(count: summary.videoCount, label: "Videos", systemImage: "film")
                }
            } else if viewModel.isLoading {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Counting your photos…")
                        .icStyle(.body)
                        .foregroundStyle(ICColor.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ICColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func statItem(count: Int, label: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(ICColor.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(ICFormat.count(count))
                    .icStyle(.bodyBold)
                    .foregroundStyle(ICColor.primaryText)
                Text(label)
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }

    /// A library with nothing in it isn't an error, but a greyed-out "Scan My Photos" with no
    /// explanation reads like one. Say why the button can't be pressed.
    private var emptyLibraryNote: some View {
        ICInfoRow(systemImage: "photo.on.rectangle",
                  title: hasLimitedAccess ? "No photos shared yet" : "No photos yet",
                  detail: hasLimitedAccess
                      ? "You haven't shared any photos with iClean, so there's nothing to look through. Tap \"Choose More Photos\" above to pick some."
                      : "There are no photos or videos on this iPhone yet, so there's nothing for iClean to look through.",
                  tint: ICColor.secondaryText)
    }

    /// Accounts for the space iClean itself uses.
    ///
    /// An app that asks people to delete photos to save space has no business quietly using
    /// tens of megabytes without saying so. Deliberately understated though — it sits at the
    /// bottom, appears only once there's something to report, and is worded as a benefit with
    /// a cost rather than a warning. Clearing is safe: it costs a slower next scan, nothing
    /// more, which is why the confirmation explains rather than cautions.
    private func cacheNote(bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ICInfoRow(systemImage: "bolt.badge.clock",
                      title: "Faster scanning",
                      detail: "iClean remembers what it already checked, so scanning again is much quicker. This uses \(ICFormat.fileSize(bytes)) on your iPhone.",
                      tint: ICColor.secondaryText)

            ICButton(title: "Clear Saved Data",
                     systemImage: "trash",
                     role: .secondary) {
                showingClearCacheConfirmation = true
            }
        }
        .padding(16)
        .background(ICColor.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .alert("Clear saved scanning data?", isPresented: $showingClearCacheConfirmation) {
            Button("Keep It", role: .cancel) {}
            Button("Clear") {
                Task { await viewModel.clearCache() }
            }
        } message: {
            Text("This frees \(ICFormat.fileSize(bytes)). Your photos are not affected — nothing is deleted from your library. The next scan will simply take longer, because iClean will check everything again from scratch.")
        }
    }

    private var recentPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent")
                .icStyle(.sectionTitle)
                .foregroundStyle(ICColor.primaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbSide), spacing: 8)], spacing: 8) {
                ForEach(viewModel.recentAssets, id: \.localIdentifier) { asset in
                    AssetThumbnailView(asset: asset, side: thumbSide)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview of your recent photos")
    }
}

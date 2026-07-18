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

    private let thumbSide: CGFloat = 72

    var body: some View {
        ICScreen {
            if hasLimitedAccess {
                LimitedAccessBanner(onChooseMore: onChooseMorePhotos)
            }

            header

            summaryCard

            if !viewModel.recentAssets.isEmpty {
                recentPreview
            }
        } footer: {
            ICButton(title: "Scan My Photos",
                     systemImage: "magnifyingglass",
                     isEnabled: (viewModel.summary?.totalCount ?? 0) > 0,
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
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(ICColor.primaryText)
                    .accessibilityLabel("\(summary.totalCount) items in your library")
                Text("items in total")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)

                Divider()

                HStack(spacing: 24) {
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

import SwiftUI
import Photos

/// Drives the Home screen: loads the library summary and a few recent assets for the
/// preview grid. Detection/scanning is added in M2; for now "Scan" is not yet active.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var summary: LibrarySummary?
    @Published private(set) var recentAssets: [PHAsset] = []
    @Published private(set) var isLoading = false

    private let fetcher = PhotoLibraryFetcher()
    private static let previewCount = 12

    /// Loads (or reloads) the library summary and preview assets. Safe to call on appear.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Kick off both reads concurrently.
        async let summary = fetcher.loadSummary()
        async let recents = fetcher.loadRecentAssets(limit: Self.previewCount)
        self.summary = await summary
        self.recentAssets = await recents
    }
}

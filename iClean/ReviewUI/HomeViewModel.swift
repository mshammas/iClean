import SwiftUI
import Photos

/// Drives the Home screen: loads the library summary and a few recent assets for the
/// preview grid. Detection/scanning is added in M2; for now "Scan" is not yet active.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var summary: LibrarySummary?
    @Published private(set) var recentAssets: [PHAsset] = []
    @Published private(set) var isLoading = false
    /// Bytes the scan cache is using, or `nil` when there's too little to be worth mentioning.
    @Published private(set) var cacheBytes: Int64?

    private let fetcher = PhotoLibraryFetcher()
    private let cache = ScanCacheStore.shared
    private static let previewCount = 12

    /// Below this the cache isn't worth putting on screen. An app about reclaiming storage
    /// should account for what it uses, but not make a fuss over a rounding error — before the
    /// first scan there is nothing to report, and saying so would only raise a question the
    /// user didn't have.
    private static let cacheVisibilityThreshold: Int64 = 1024 * 1024

    /// Loads (or reloads) the library summary and preview assets. Safe to call on appear.
    func load() async {
        isLoading = true
        defer { isLoading = false }

        // Kick off both reads concurrently.
        async let summary = fetcher.loadSummary()
        async let recents = fetcher.loadRecentAssets(limit: Self.previewCount)
        self.summary = await summary
        self.recentAssets = await recents

        await refreshCacheSize()
    }

    func refreshCacheSize() async {
        let bytes = await cache.sizeOnDisk()
        cacheBytes = bytes >= Self.cacheVisibilityThreshold ? bytes : nil
    }

    /// Throws away every stored measurement. Costs nothing but time — the next scan simply
    /// re-measures — so it is safe to offer without ceremony.
    func clearCache() async {
        await cache.clear()
        await refreshCacheSize()
    }
}

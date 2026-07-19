import SwiftUI
import Photos

/// Drives the whole scan → review → delete flow.
///
/// Owns the scan lifecycle, the current results, and the user's selection. Screens read
/// from it and call into it; it never touches PhotoKit directly beyond the coordinator
/// and deletion manager.
@MainActor
final class CleanupViewModel: ObservableObject {

    enum ScanState {
        case idle
        case scanning(ScanProgress)
        case completed(ScanResults)
        case failed(String)
    }

    /// A problem worth interrupting the user about, shown as an alert.
    struct UserAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var selection = ReviewSelection()
    @Published private(set) var isDeleting = false
    /// Set when a scan or delete goes wrong (including the user declining iOS's own
    /// delete confirmation). Cleared when the alert is dismissed.
    @Published var alert: UserAlert?
    /// Groups where the user has chosen a different copy to keep than the app suggested.
    @Published private var keeperOverrides: [UUID: DuplicateGroup] = [:]
    /// Items already deleted this session. Filtered out of everything the UI shows, so
    /// deleting part-way through a review doesn't leave rows pointing at gone photos.
    @Published private(set) var deletedIDs: Set<String> = []
    /// Bumped after every successful deletion so Home knows to re-read the library counts.
    @Published private(set) var completedDeletions = 0

    private let coordinator = DetectionCoordinator()
    private let deletionManager = DeletionManager()

    // MARK: Derived state

    var results: ScanResults? {
        if case .completed(let results) = scanState { return results }
        return nil
    }

    var isScanning: Bool {
        if case .scanning = scanState { return true }
        return false
    }

    var progress: ScanProgress {
        if case .scanning(let progress) = scanState { return progress }
        return .zero
    }

    var selectedCount: Int { selection.count }

    var selectedBytes: Int64 {
        // `selectedBytes` counts each asset once, so overlapping categories are safe.
        selection.selectedBytes(in: CleanupCategory.allCases.flatMap(candidates(in:)))
    }

    /// Categories that still have something to review. Derived live, so a category empties
    /// out of the summary once its items have been deleted mid-review.
    var populatedCategories: [CleanupCategory] {
        CleanupCategory.allCases.filter { !candidates(in: $0).isEmpty }
    }

    func candidates(in category: CleanupCategory) -> [Candidate] {
        // Duplicates come from the groups rather than the raw scan output, so a user-chosen
        // keeper is reflected everywhere — counts, sizes and the delete total alike.
        guard category != .duplicates else {
            return duplicateGroups.flatMap(\.extras).sorted { $0.estimatedBytes > $1.estimatedBytes }
        }
        return (results?.candidates(in: category) ?? []).filter { !deletedIDs.contains($0.id) }
    }

    /// Duplicate clusters, largest space saving first, with any user-chosen keeper applied and
    /// already-deleted copies removed. Groups with nothing left to review drop out entirely.
    var duplicateGroups: [DuplicateGroup] {
        (results?.duplicateGroups ?? [])
            .map { keeperOverrides[$0.id] ?? $0 }
            .compactMap { group in
                let remaining = group.extras.filter { !deletedIDs.contains($0.id) }
                guard !remaining.isEmpty else { return nil }
                return DuplicateGroup(id: group.id,
                                      keeper: group.keeper,
                                      keeperReason: group.keeperReason,
                                      keeperBytes: group.keeperBytes,
                                      extras: remaining)
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Swaps which copy in a duplicate group is kept.
    ///
    /// The app's pick is only a suggestion — the user may well prefer a different copy, and
    /// without this the keeper is simply unchangeable. The previously-kept photo becomes an
    /// ordinary copy but is left **unticked**: the user is clearly weighing this group up, so
    /// nothing should quietly become marked for deletion as a side effect of the swap.
    func makeKeeper(_ candidate: Candidate) {
        guard let groupID = candidate.duplicateGroupID,
              let group = duplicateGroups.first(where: { $0.id == groupID }),
              group.keeper.localIdentifier != candidate.id else { return }

        let previousKeeper = Candidate(asset: group.keeper,
                                       category: .duplicates,
                                       reason: "Copy · \(ICFormat.fileSize(group.keeperBytes))",
                                       estimatedBytes: group.keeperBytes,
                                       duplicateGroupID: groupID,
                                       preselect: false)

        let remaining = group.extras.filter { $0.id != candidate.id }
        keeperOverrides[groupID] = DuplicateGroup(id: groupID,
                                                  keeper: candidate.asset,
                                                  keeperReason: "Keeping this one — you chose it",
                                                  keeperBytes: candidate.estimatedBytes,
                                                  extras: [previousKeeper] + remaining)

        // The copy being kept must never be ticked for deletion.
        selection.setSelected([candidate.id], to: false)
    }

    // MARK: Scanning

    /// Runs a scan to completion. The caller owns the surrounding `Task`, so cancelling
    /// that task cancels the scan (the coordinator checks for cancellation between batches).
    /// - Parameter includeICloudPhotos: opt-in deep scan that downloads iCloud-only originals
    ///   so they can be checked too. Much slower and uses network data.
    func runScan(includeICloudPhotos: Bool = false) async {
        scanState = .scanning(ScanProgress(scanned: 0,
                                           total: 0,
                                           includesICloudPhotos: includeICloudPhotos))
        do {
            let results = try await coordinator.scan(includeICloudPhotos: includeICloudPhotos) { progress in
                // Progress arrives off the main actor; hop before touching UI state.
                Task { @MainActor [weak self] in
                    // Ignore late progress that lands after the scan already finished.
                    guard let self, self.isScanning else { return }
                    self.scanState = .scanning(progress)
                }
            }
            try Task.checkCancellation()
            scanState = .completed(results)
            // Apply the safe defaults: only duplicate extras start ticked.
            selection = ReviewSelection(selectedIDs: results.defaultSelectedIDs)
        } catch is CancellationError {
            scanState = .idle
        } catch {
            scanState = .failed(error.localizedDescription)
            // Surface it — a scan that silently does nothing is worse than an error.
            alert = UserAlert(title: "Couldn't check your photos",
                              message: "Something went wrong while looking through your library. Please try again.")
        }
    }

    /// Clears results and selection, e.g. after finishing a deletion.
    func reset() {
        scanState = .idle
        selection.removeAll()
        keeperOverrides.removeAll()
        deletedIDs.removeAll()
    }

    // MARK: Selection

    func toggle(_ candidate: Candidate) {
        selection.toggle(candidate.id)
    }

    func setAll(in category: CleanupCategory, selected: Bool) {
        selection.setSelected(candidates(in: category).map(\.id), to: selected)
    }

    // MARK: Deletion

    /// Deletes everything currently ticked, across all categories.
    func performDeletion() async -> DeletionResult? {
        await delete(ids: Array(selection.selectedIDs), estimatedBytes: selectedBytes)
    }

    /// Deletes just the ticked copies in one duplicate group.
    ///
    /// Exists so a long review doesn't have to be completed in one sitting: the clear-cut
    /// groups can be dealt with as they're confirmed, rather than holding every decision in
    /// mind until the end. The keeper is never included, so the group keeps a copy.
    func deleteTicked(in group: DuplicateGroup) async -> DeletionResult? {
        let ticked = group.extras.filter { selection.isSelected($0.id) }
        guard !ticked.isEmpty else { return nil }
        return await delete(ids: ticked.map(\.id),
                            estimatedBytes: ticked.reduce(0) { $0 + $1.estimatedBytes })
    }

    /// The single place deletion actually happens. Returns the result on success, or `nil`
    /// if it failed or the user declined iOS's own confirmation (`alert` explains which).
    private func delete(ids: [String], estimatedBytes: Int64) async -> DeletionResult? {
        guard !ids.isEmpty else { return nil }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let result = try await deletionManager.delete(localIdentifiers: ids,
                                                          estimatedBytes: estimatedBytes)
            // Drop them from view state so the UI can't show rows for deleted photos.
            deletedIDs.formUnion(ids)
            selection.setSelected(ids, to: false)
            completedDeletions += 1
            return result
        } catch {
            let message = (error as? DeletionError)?.errorDescription
                ?? error.localizedDescription
            // Declining iOS's own confirmation is a normal choice, not a failure —
            // word it calmly either way.
            let isCancellation = (error as? DeletionError).map {
                if case .cancelledByUser = $0 { return true } else { return false }
            } ?? false
            alert = UserAlert(title: isCancellation ? "Nothing deleted" : "Couldn't delete",
                              message: message)
            return nil
        }
    }
}

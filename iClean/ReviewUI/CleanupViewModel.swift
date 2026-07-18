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
        guard let results else { return 0 }
        return selection.selectedBytes(in: results.candidates)
    }

    func candidates(in category: CleanupCategory) -> [Candidate] {
        results?.candidates(in: category) ?? []
    }

    /// Duplicate clusters, largest space saving first.
    var duplicateGroups: [DuplicateGroup] {
        (results?.duplicateGroups ?? []).sorted { $0.reclaimableBytes > $1.reclaimableBytes }
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
    }

    // MARK: Selection

    func toggle(_ candidate: Candidate) {
        selection.toggle(candidate.id)
    }

    func setAll(in category: CleanupCategory, selected: Bool) {
        selection.setSelected(candidates(in: category).map(\.id), to: selected)
    }

    // MARK: Deletion

    /// Performs the batch delete. Returns the result on success, or `nil` if it failed or
    /// the user backed out (in which case `deletionMessage` explains what happened).
    func performDeletion() async -> DeletionResult? {
        guard !selection.isEmpty else { return nil }

        isDeleting = true
        defer { isDeleting = false }

        do {
            let result = try await deletionManager.delete(
                localIdentifiers: Array(selection.selectedIDs),
                estimatedBytes: selectedBytes
            )
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

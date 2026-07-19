import SwiftUI

/// Steps in the cleanup flow. Kept flat (a simple array path) so navigation stays shallow
/// and predictable: Home → Summary → Category, and Summary → Confirm → Result.
enum CleanupRoute: Hashable {
    case summary
    case category(CleanupCategory)
    case confirm
    case result(DeletionResult)
}

/// Owns the cleanup flow: the shared view model, the navigation path, and the scan task.
/// `RootView` shows this once the user has photo access.
struct CleanupFlowView: View {
    let hasLimitedAccess: Bool
    let onChooseMorePhotos: () -> Void

    @StateObject private var viewModel = CleanupViewModel()
    @State private var path: [CleanupRoute] = []
    @State private var scanTask: Task<Void, Never>?

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: CleanupRoute.self, destination: destination)
        }
        .alert(viewModel.alert?.title ?? "",
               isPresented: Binding(get: { viewModel.alert != nil },
                                    set: { if !$0 { viewModel.alert = nil } })) {
            Button("OK", role: .cancel) { viewModel.alert = nil }
        } message: {
            Text(viewModel.alert?.message ?? "")
        }
    }

    // MARK: Screens

    @ViewBuilder
    private var root: some View {
        if viewModel.isScanning {
            ScanningView(progress: viewModel.progress, onCancel: cancelScan)
        } else {
            HomeView(hasLimitedAccess: hasLimitedAccess,
                     onChooseMorePhotos: onChooseMorePhotos,
                     // Driven by the view model so *any* deletion refreshes the counts,
                     // including the per-group deletes done mid-review.
                     refreshToken: viewModel.completedDeletions,
                     onScan: { startScan() })
        }
    }

    @ViewBuilder
    private func destination(for route: CleanupRoute) -> some View {
        switch route {
        case .summary:
            ScanSummaryView(viewModel: viewModel,
                            hasLimitedAccess: hasLimitedAccess,
                            onOpenCategory: { path.append(.category($0)) },
                            onDelete: { path.append(.confirm) },
                            onCheckICloudPhotos: { startScan(includeICloudPhotos: true) })

        case .category(let category):
            // Duplicates get their own grouped screen — they're the only pre-ticked
            // category, so the review has to lead with what's being kept.
            if category == .duplicates {
                DuplicateReviewView(viewModel: viewModel)
            } else {
                CategoryReviewView(category: category, viewModel: viewModel)
            }

        case .confirm:
            DeleteConfirmationView(viewModel: viewModel,
                                   onConfirm: confirmDeletion,
                                   onCancel: { path.removeLast() })

        case .result(let result):
            DeletionResultView(result: result, onDone: finish)
        }
    }

    // MARK: Actions

    private func startScan(includeICloudPhotos: Bool = false) {
        scanTask?.cancel()
        // Drop back to the root so the scanning screen is what's on show. Re-scanning from
        // the summary (the iCloud opt-in) would otherwise leave stale results underneath.
        path.removeAll()
        scanTask = Task {
            await viewModel.runScan(includeICloudPhotos: includeICloudPhotos)
            // Only advance if the scan actually produced results (not cancelled/failed).
            if viewModel.results != nil {
                path.append(.summary)
            }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
    }

    private func confirmDeletion() {
        Task {
            if let result = await viewModel.performDeletion() {
                // Replace the stack so there's no going "back" into a stale review list.
                path = [.result(result)]
            }
            // On failure `deletionMessage` is set and the alert explains what happened.
        }
    }

    private func finish() {
        path.removeAll()
        viewModel.reset()
    }
}

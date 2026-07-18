import SwiftUI
import Photos
import Combine

/// The screen the app should currently show. Derived from onboarding completion
/// and the current Photos authorization status. Kept deliberately shallow — the
/// app should never bury the user more than a couple of levels deep.
enum AppStage: Equatable {
    case onboarding
    case permissionPrimer
    case permissionDenied
    case home            // full or limited access both land here; limited shows a banner
}

/// Top-level app state. Owns the authorization manager and decides which stage to show.
///
/// This is the single source of truth injected into the environment. Screen-specific
/// ViewModels are created by their screens; `AppState` only holds cross-cutting state
/// (onboarding + permission) that decides top-level routing.
///
/// Because SwiftUI views observe `AppState`, we mirror the auth manager's `@Published`
/// status into our own published property so permission changes trigger a re-render.
@MainActor
final class AppState: ObservableObject {
    let authManager: PhotoLibraryAuthorizationManager

    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var authStatus: PHAuthorizationStatus

    private var cancellables = Set<AnyCancellable>()
    private static let onboardingKey = "hasCompletedOnboarding"

    /// Default init. Kept separate from the injecting init below because a default
    /// argument expression is evaluated in a nonisolated context, which can't call
    /// the `@MainActor` authorization manager's initializer.
    convenience init() {
        self.init(authManager: PhotoLibraryAuthorizationManager())
    }

    init(authManager: PhotoLibraryAuthorizationManager) {
        self.authManager = authManager
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        self.authStatus = authManager.status

        authManager.$status
            .removeDuplicates()
            .sink { [weak self] status in self?.authStatus = status }
            .store(in: &cancellables)
    }

    /// Computed routing target. Order matters: onboarding first, then permission,
    /// then the main app.
    var stage: AppStage {
        if !hasCompletedOnboarding {
            return .onboarding
        }
        switch authStatus {
        case .authorized, .limited:
            return .home
        case .denied, .restricted:
            return .permissionDenied
        case .notDetermined:
            return .permissionPrimer
        @unknown default:
            return .permissionPrimer
        }
    }

    /// True when the user granted only a subset of their library. The Home screen
    /// uses this to show a banner and adjust its copy.
    var hasLimitedAccess: Bool { authStatus == .limited }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
    }

    /// Re-reads the current authorization status (e.g. after returning from Settings).
    func refreshAuthorizationStatus() {
        authManager.refreshStatus()
    }
}

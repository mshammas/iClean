import SwiftUI
import UIKit
import PhotosUI

/// Top-level view. Chooses which screen to show based on `AppState.stage`, and wires up
/// the side effects that need UIKit or async work: requesting permission, opening Settings,
/// presenting the limited-library picker, and re-checking access on foreground.
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .animation(.default, value: appState.stage)
            .onChange(of: scenePhase) { _, newPhase in
                // The user may grant/revoke access in Settings and return; re-check.
                if newPhase == .active {
                    appState.refreshAuthorizationStatus()
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch appState.stage {
        case .onboarding:
            OnboardingView(onContinue: appState.completeOnboarding)

        case .permissionPrimer:
            PermissionPrimerView(onAllow: requestPhotoAccess)

        case .permissionDenied:
            PermissionDeniedView(onOpenSettings: openSettings)

        case .home:
            CleanupFlowView(hasLimitedAccess: appState.hasLimitedAccess,
                            onChooseMorePhotos: presentLimitedPicker)
        }
    }

    // MARK: - Side effects

    private func requestPhotoAccess() {
        Task { await appState.authManager.requestAccess() }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func presentLimitedPicker() {
        guard let controller = UIApplication.shared.topViewController else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

// MARK: - UIKit bridge

extension UIApplication {
    /// The topmost presented view controller of the active foreground scene.
    /// Needed to present PhotoKit's limited-library picker from SwiftUI.
    var topViewController: UIViewController? {
        let keyWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

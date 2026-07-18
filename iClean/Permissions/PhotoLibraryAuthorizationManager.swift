import Foundation
import Photos

/// Wraps `PHPhotoLibrary` authorization so the rest of the app can observe a single
/// `@Published` status and request access without touching PhotoKit directly.
///
/// We always request `.readWrite` access: reading is needed to scan the library and
/// writing is needed to move unwanted items to Recently Deleted.
@MainActor
final class PhotoLibraryAuthorizationManager: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus

    init() {
        self.status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Presents the system permission prompt (only if status is `.notDetermined`;
    /// otherwise the completion just reflects the existing status).
    func requestAccess() async {
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.status = newStatus
    }

    /// Re-reads the current status without prompting. Call when returning to the
    /// foreground, since the user may have changed access in Settings.
    func refreshStatus() {
        self.status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }
}

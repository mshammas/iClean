import SwiftUI

/// Shown when Photos access is denied or restricted. iClean can't work without it,
/// so we explain plainly and offer a one-tap route to the Settings app.
struct PermissionDeniedView: View {
    /// Opens the app's page in Settings so the user can turn access on.
    let onOpenSettings: () -> Void

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.slash")
                    .font(.system(size: 56))
                    .foregroundStyle(ICColor.warning)
                    .accessibilityHidden(true)

                Text("iClean needs photo access")
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)

                Text("Photo access is currently turned off, so iClean can't check your library. You can turn it on in Settings.")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("How to turn it on")
                    .icStyle(.sectionTitle)
                    .foregroundStyle(ICColor.primaryText)
                Text("1. Tap the button below to open Settings.\n2. Tap \"Photos\".\n3. Choose \"Full Access\".\n4. Come back to iClean.")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            ICButton(title: "Open Settings", systemImage: "gearshape", action: onOpenSettings)
        }
    }
}

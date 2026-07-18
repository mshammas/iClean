import SwiftUI

/// Shown before the system Photos prompt. Explains *why* we need access in plain
/// language, which both respects the user and improves the chance they allow it.
/// Tapping "Allow Access" triggers the real system prompt.
struct PermissionPrimerView: View {
    /// Called when the user asks to grant access. The parent runs the async request.
    let onAllow: () -> Void

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 56))
                    .foregroundStyle(ICColor.primary)
                    .accessibilityHidden(true)

                Text("Allow access to your photos")
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)

                Text("iClean needs permission to look through your photos and videos so it can find the ones worth clearing out.")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ICInfoRow(systemImage: "iphone",
                      title: "Everything stays on your iPhone",
                      detail: "Your photos are checked right here on your device. Nothing is uploaded anywhere.")
            ICInfoRow(systemImage: "hand.raised",
                      title: "You're always in control",
                      detail: "iClean only makes suggestions. Nothing is deleted until you review and confirm.")

            Text("On the next screen, tap \"Allow Full Access\" so iClean can check your whole library.")
                .icStyle(.caption)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            ICButton(title: "Allow Access", systemImage: "checkmark.shield", action: onAllow)
        }
    }
}

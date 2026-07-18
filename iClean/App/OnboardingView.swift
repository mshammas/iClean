import SwiftUI

/// First-run welcome. One screen, plain language, a single clear action.
/// Explains what the app does before we ever ask for permission.
struct OnboardingView: View {
    let onContinue: () -> Void

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(ICColor.primary)
                    .accessibilityHidden(true)

                Text("Welcome to iClean")
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)

                Text("Free up space by clearing out photos and videos you don't need.")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 8)

            ICInfoRow(systemImage: "rectangle.stack.badge.minus",
                      title: "Finds duplicates",
                      detail: "Spots copies of the same photo so you can keep just one.")
            ICInfoRow(systemImage: "camera.filters",
                      title: "Finds blurry shots",
                      detail: "Points out photos that came out out-of-focus.")
            ICInfoRow(systemImage: "camera.viewfinder",
                      title: "Finds screenshots",
                      detail: "Gathers up screenshots that pile up over time.")
            ICInfoRow(systemImage: "film",
                      title: "Finds large videos",
                      detail: "Shows big videos that take up the most space.")

            Text("Nothing is deleted without your say-so. You review everything first, and deleted items wait 30 days in your Recently Deleted album in case you change your mind.")
                .icStyle(.caption)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        } footer: {
            ICButton(title: "Continue", systemImage: "arrow.right", action: onContinue)
        }
    }
}

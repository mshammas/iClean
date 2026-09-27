import SwiftUI

/// Confirmation that the delete worked, and a reminder of where the items went.
struct DeletionResultView: View {
    let result: DeletionResult
    let onDone: () -> Void

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .icIconSize(64)
                    .foregroundStyle(ICColor.success)
                    .accessibilityHidden(true)

                Text("All done!")
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)

                Text("\(ICFormat.items(result.deletedCount)) \(result.deletedCount == 1 ? "was" : "were") moved to Recently Deleted, freeing up about \(ICFormat.fileSize(result.estimatedBytes)).")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ICInfoRow(systemImage: "clock.arrow.circlepath",
                      title: "Changed your mind?",
                      detail: "Open the Photos app, go to Albums, and look for Recently Deleted. Your items are there for 30 days.",
                      tint: ICColor.success)

            ICInfoRow(systemImage: "icloud",
                      title: "Your space is on its way back",
                      detail: "The space is fully freed once these items leave Recently Deleted, or when you empty that album yourself.",
                      tint: ICColor.primary)
        } footer: {
            ICButton(title: "Done", systemImage: "house", action: onDone)
        }
        .navigationTitle("Finished")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
    }
}

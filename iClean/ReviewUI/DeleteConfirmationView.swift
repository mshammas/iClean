import SwiftUI

/// The final gate before anything is deleted. States plainly what will happen, how much
/// space it frees, and that Recently Deleted is the safety net.
///
/// iOS shows its own "Delete N items?" alert on top of this, so the user confirms twice.
struct DeleteConfirmationView: View {
    @ObservedObject var viewModel: CleanupViewModel
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ICScreen {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .icIconSize(56)
                    .foregroundStyle(ICColor.destructive)
                    .accessibilityHidden(true)

                Text("Delete \(ICFormat.items(viewModel.selectedCount))?")
                    .icStyle(.screenTitle)
                    .foregroundStyle(ICColor.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This will free up about \(ICFormat.fileSize(viewModel.selectedBytes)).")
                    .icStyle(.body)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ICInfoRow(systemImage: "clock.arrow.circlepath",
                      title: "You have 30 days to change your mind",
                      detail: "Deleted items move to the Recently Deleted album in your Photos app. They're only gone for good after 30 days.",
                      tint: ICColor.success)

            ICInfoRow(systemImage: "icloud",
                      title: "This also frees up iCloud space",
                      detail: "Because your photos sync with iCloud, deleting them here clears the space there too.",
                      tint: ICColor.primary)

            Text("Your iPhone will ask you to confirm once more before anything is deleted.")
                .icStyle(.caption)
                .foregroundStyle(ICColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        } footer: {
            VStack(spacing: 12) {
                ICButton(title: viewModel.isDeleting ? "Deleting…" : "Yes, Delete",
                         systemImage: "trash",
                         role: .destructive,
                         isEnabled: !viewModel.isDeleting,
                         action: onConfirm)
                ICButton(title: "Keep Everything",
                         systemImage: "arrow.uturn.backward",
                         role: .secondary,
                         isEnabled: !viewModel.isDeleting,
                         action: onCancel)
            }
        }
        .navigationTitle("Confirm")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

/// A single explanatory row: a large icon, a title, and a short description.
/// Used on onboarding and permission screens to explain the app in plain language.
struct ICInfoRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var tint: Color = ICColor.primary

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(tint)
                .frame(width: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .icStyle(.bodyBold)
                    .foregroundStyle(ICColor.primaryText)
                Text(detail)
                    .icStyle(.caption)
                    .foregroundStyle(ICColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

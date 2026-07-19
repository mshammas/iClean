import SwiftUI

/// Visual role of a button.
enum ICButtonRole {
    case primary      // the main action on a screen
    case secondary    // an alternative / less prominent action
    case destructive  // the final delete action

    var background: Color {
        switch self {
        case .primary:     return ICColor.primary
        case .secondary:   return ICColor.cardBackground
        case .destructive: return ICColor.destructive
        }
    }

    var foreground: Color {
        switch self {
        case .primary, .destructive: return .white
        case .secondary:             return ICColor.primaryText
        }
    }
}

/// A large, high-contrast, full-width button with a generous tap target.
///
/// Elder-friendly: minimum height well above the 44pt HIG floor, big rounded shape,
/// bold text that scales with Dynamic Type, and an optional leading SF Symbol.
struct ICButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ICButtonRole = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with the text, so the button stays proportionate rather than becoming a thin
    /// strip wrapped around four lines of very large type.
    @ScaledMetric(relativeTo: .title3) private var minHeight: CGFloat = 60

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // The icon is decoration; at accessibility sizes the label needs the width
                // more than the button needs a symbol.
                if let systemImage, !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: systemImage)
                        .imageScale(.large)
                }
                Text(title)
                    .icStyle(.button)
                    .multilineTextAlignment(.center)
                    // Titles carry counts and sizes ("Delete 262 items") — they must wrap
                    // rather than truncate, or the user can't tell what they're confirming.
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .foregroundStyle(role.foreground)
            .background(role.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(.isButton)
    }
}

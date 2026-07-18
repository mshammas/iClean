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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.large)
                }
                Text(title)
                    .icStyle(.button)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 60)
            .padding(.vertical, 6)
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

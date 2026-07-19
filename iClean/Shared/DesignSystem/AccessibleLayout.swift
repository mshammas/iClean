import SwiftUI

/// A row that stops being a row at the accessibility text sizes.
///
/// At AX1–AX5 the "icon · text · control" pattern breaks down: the icon and the control keep
/// their width while the text column collapses to a few characters per line, so a short
/// sentence becomes a tall ragged ribbon. Stacking vertically instead gives the text the full
/// width it needs.
///
/// This app's audience skews elderly, so the largest text sizes are a first-class case rather
/// than graceful degradation — expect real users at AX3 and above.
struct ICAdaptiveStack<Content: View>: View {
    var horizontalSpacing: CGFloat = 16
    var verticalSpacing: CGFloat = 12
    /// Vertical alignment used while laid out horizontally.
    var rowAlignment: VerticalAlignment = .center
    /// Horizontal alignment used once stacked.
    var stackAlignment: HorizontalAlignment = .leading
    @ViewBuilder var content: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: stackAlignment, spacing: verticalSpacing, content: content)
        } else {
            HStack(alignment: rowAlignment, spacing: horizontalSpacing, content: content)
        }
    }
}

/// Scales a fixed icon point size with the user's text size.
///
/// `.font(.system(size: 56))` is frozen — it ignores Dynamic Type entirely. Beside AX5 body
/// text a 56pt hero icon reads as a stray dot, which is exactly backwards for someone who
/// turned the text up because they can't see small things.
private struct ICScaledIconSize: ViewModifier {
    let base: CGFloat
    let weight: Font.Weight
    /// A pure multiplier: `@ScaledMetric` scales the value 1 by the current text size, which
    /// gives the growth factor to apply to any base dimension.
    @ScaledMetric(relativeTo: .largeTitle) private var multiplier: CGFloat = 1

    func body(content: Content) -> some View {
        content.font(.system(size: base * multiplier, weight: weight))
    }
}

extension View {
    /// Sizes a decorative SF Symbol so it grows with Dynamic Type.
    func icIconSize(_ base: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ICScaledIconSize(base: base, weight: weight))
    }
}

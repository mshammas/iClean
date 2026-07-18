import SwiftUI

/// Typography for iClean.
///
/// Elder-friendly principles:
/// - Every style is built on a Dynamic Type text style (`.largeTitle`, `.body`, …) so
///   it scales with the user's system text-size setting, including the Accessibility sizes.
/// - We use the rounded design for a softer, friendlier, highly legible feel.
/// - Base weights lean bold for legibility.
///
/// Use these via the `View` helpers below, e.g. `Text("Hi").icStyle(.screenTitle)`.
enum ICTextStyle {
    case screenTitle     // big screen headline
    case sectionTitle    // group / card heading
    case body            // primary reading text
    case bodyBold
    case caption         // supporting detail (sizes, counts)
    case button          // button labels

    var font: Font {
        switch self {
        case .screenTitle:  return .system(.largeTitle, design: .rounded).weight(.bold)
        case .sectionTitle: return .system(.title2, design: .rounded).weight(.semibold)
        case .body:         return .system(.title3, design: .rounded)            // note: title3, not body — bumps base size up
        case .bodyBold:     return .system(.title3, design: .rounded).weight(.semibold)
        case .caption:      return .system(.body, design: .rounded)              // "caption" here is still body-sized for legibility
        case .button:       return .system(.title3, design: .rounded).weight(.bold)
        }
    }
}

extension View {
    /// Applies an iClean text style. Kept as a helper so the base sizes live in one place.
    func icStyle(_ style: ICTextStyle) -> some View {
        self.font(style.font)
    }
}

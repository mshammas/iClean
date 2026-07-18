import SwiftUI

/// Semantic colors for iClean. High-contrast and adaptive to light/dark mode.
///
/// We use system-provided adaptive colors where possible (they already meet contrast
/// guidelines and respond to Increase Contrast), and only define our own accents.
enum ICColor {
    /// Primary action color — used for the main "do it" buttons (Scan, Continue).
    static let primary = Color.accentColor

    /// Destructive action color — used only for the final delete confirmation.
    static let destructive = Color(.systemRed)

    /// Standard screen background.
    static let background = Color(.systemBackground)

    /// Slightly raised surfaces like cards.
    static let cardBackground = Color(.secondarySystemBackground)

    /// Primary readable text.
    static let primaryText = Color(.label)

    /// Secondary/supporting text — still meets contrast, just de-emphasized.
    static let secondaryText = Color(.secondaryLabel)

    /// Success / positive space-freed messaging.
    static let success = Color(.systemGreen)

    /// Warning banner (e.g. limited photo access).
    static let warning = Color(.systemOrange)
}

import SwiftUI

struct AppTheme: Equatable {
    let name: String
    let background: Color
    let card: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let success: Color
    let warning: Color
    let danger: Color
    let cornerRadius: CGFloat
    let shadowOpacity: Double
    let fontDesign: Font.Design
    let panelMaterial: NSVisualEffectView.Material
    let cardOpacity: Double
    let statusBarTextColor: NSColor
    let forceDarkAppearance: Bool

    static func == (lhs: AppTheme, rhs: AppTheme) -> Bool { lhs.name == rhs.name }
}

extension AppTheme {
    static let classic = AppTheme(
        name: "Classic",
        background: Color(nsColor: .windowBackgroundColor),
        card: Color(nsColor: .controlBackgroundColor),
        primaryText: Color(nsColor: .labelColor),
        secondaryText: Color(nsColor: .secondaryLabelColor),
        accent: .blue, success: .green, warning: .yellow, danger: .red,
        cornerRadius: 12, shadowOpacity: 0.08, fontDesign: .rounded,
        panelMaterial: .sidebar, cardOpacity: 0.6,
        statusBarTextColor: .labelColor,
        forceDarkAppearance: false
    )

    static let compact = AppTheme(
        name: "Compact",
        background: Color(nsColor: .windowBackgroundColor),
        card: Color(nsColor: .controlBackgroundColor).opacity(0.5),
        primaryText: Color(nsColor: .labelColor),
        secondaryText: Color(nsColor: .secondaryLabelColor),
        accent: .blue, success: .green, warning: .orange, danger: .red,
        cornerRadius: 8, shadowOpacity: 0.04, fontDesign: .monospaced,
        panelMaterial: .menu, cardOpacity: 0.4,
        statusBarTextColor: .labelColor,
        forceDarkAppearance: false
    )

    /// Terminal: always dark. Green phosphor on black, monospace, zero decoration.
    static let terminal = AppTheme(
        name: "Terminal",
        background: Color(red: 0.04, green: 0.06, blue: 0.04),
        card: Color(red: 0.07, green: 0.10, blue: 0.07),
        primaryText: Color(red: 0.15, green: 0.97, blue: 0.15),
        secondaryText: Color(red: 0.10, green: 0.60, blue: 0.10),
        accent: Color(red: 0.15, green: 0.97, blue: 0.15),
        success: Color(red: 0.15, green: 0.97, blue: 0.15),
        warning: Color(red: 0.90, green: 0.80, blue: 0.10),
        danger: Color(red: 0.95, green: 0.25, blue: 0.25),
        cornerRadius: 0, shadowOpacity: 0, fontDesign: .monospaced,
        panelMaterial: .underWindowBackground, cardOpacity: 0.85,
        statusBarTextColor: NSColor(red: 0.15, green: 0.97, blue: 0.15, alpha: 1),
        forceDarkAppearance: true
    )

    /// Glass: expose macOS itself. No custom palette — just system materials and native colors.
    static let glass = AppTheme(
        name: "Glass",
        background: Color.clear,
        card: Color.clear,
        primaryText: Color.primary,
        secondaryText: Color.secondary,
        accent: Color.accentColor,
        success: Color.green,
        warning: Color.orange,
        danger: Color.red,
        cornerRadius: 16, shadowOpacity: 0.18, fontDesign: .rounded,
        panelMaterial: .hudWindow, cardOpacity: 0,
        statusBarTextColor: .labelColor,
        forceDarkAppearance: false
    )
}

extension AppTheme {
    func colorForUsage(_ usage: Double) -> Color {
        if usage < 50 { return success }
        if usage < 80 { return warning }
        return danger
    }
}

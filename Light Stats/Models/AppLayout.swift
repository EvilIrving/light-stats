import Foundation

// MARK: - Navigation Style

enum NavigationStyle: String, CaseIterable {
    case topTabs
    case floatingSegment
    case compactHeader
    case iconOnlyBottom
}

// MARK: - Overview Style

enum OverviewStyle: String, CaseIterable {
    case cards
    case compactGrid
    case terminalRows
    case glassCards
}

// MARK: - Status Bar Style

enum StatusBarStyle: String, CaseIterable {
    case stackedLabelValue
    case compactMicro
    case terminalInline
}

// MARK: - Card Style

enum CardStyle: String, CaseIterable {
    case bento
    case flat
    case glass
    case minimal
}

// MARK: - Layout Density

enum LayoutDensity: String, CaseIterable {
    case comfortable
    case compact
    case spacious
}

// MARK: - App Layout

struct AppLayout: Equatable {
    let name: String
    let popoverSize: CGSize
    let navigationStyle: NavigationStyle
    let overviewStyle: OverviewStyle
    let cardStyle: CardStyle
    let statusBarStyle: StatusBarStyle
    let density: LayoutDensity
    let spacing: CGFloat
    let horizontalPadding: CGFloat
}

// MARK: - Preset Layouts

extension AppLayout {
    static let classic = AppLayout(
        name: "Classic",
        popoverSize: CGSize(width: 360, height: 520),
        navigationStyle: .topTabs,
        overviewStyle: .cards,
        cardStyle: .bento,
        statusBarStyle: .stackedLabelValue,
        density: .comfortable,
        spacing: 12,
        horizontalPadding: 16
    )

    static let compact = AppLayout(
        name: "Compact",
        popoverSize: CGSize(width: 360, height: 520),
        navigationStyle: .iconOnlyBottom,
        overviewStyle: .compactGrid,
        cardStyle: .minimal,
        statusBarStyle: .compactMicro,
        density: .compact,
        spacing: 6,
        horizontalPadding: 10
    )

    static let terminal = AppLayout(
        name: "Terminal",
        popoverSize: CGSize(width: 360, height: 520),
        navigationStyle: .compactHeader,
        overviewStyle: .terminalRows,
        cardStyle: .flat,
        statusBarStyle: .terminalInline,
        density: .compact,
        spacing: 2,
        horizontalPadding: 12
    )

    static let glass = AppLayout(
        name: "Glass",
        popoverSize: CGSize(width: 360, height: 520),
        navigationStyle: .floatingSegment,
        overviewStyle: .glassCards,
        cardStyle: .glass,
        statusBarStyle: .stackedLabelValue,
        density: .spacious,
        spacing: 16,
        horizontalPadding: 20
    )
}

// MARK: - Appearance Preset

enum AppearancePreset: String, CaseIterable, Identifiable {
    case classic
    case compact
    case terminal
    case glass

    var id: String { rawValue }

    var theme: AppTheme {
        switch self {
        case .classic: return .classic
        case .compact: return .compact
        case .terminal: return .terminal
        case .glass: return .glass
        }
    }

    var layout: AppLayout {
        switch self {
        case .classic: return .classic
        case .compact: return .compact
        case .terminal: return .terminal
        case .glass: return .glass
        }
    }

    var displayName: String {
        switch self {
        case .classic: return "theme.classic".localized
        case .compact: return "theme.compact".localized
        case .terminal: return "theme.terminal".localized
        case .glass: return "theme.glass".localized
        }
    }
}

//
//  ThemeChromeStyle.swift
//  Light Stats
//
//  Component-level visual language. This is independent from ThemeLayout:
//  themes can share information geometry while using different typography,
//  surface, tab, and signal treatments.
//

import SwiftUI

enum ThemeChromeStyle: Equatable, Sendable {
    case standard
    case neon
    case nightBar

    var usesNeonTreatment: Bool { self == .neon }
    var usesNightBarTreatment: Bool { self == .nightBar }
    var usesIlluminatedTreatment: Bool { self != .standard }

    var sectionTitleFont: Font {
        switch self {
        case .standard: return .system(size: 10, weight: .semibold, design: .monospaced)
        case .neon: return .system(size: 9, weight: .bold, design: .monospaced)
        case .nightBar: return .system(size: 9, weight: .bold, design: .rounded)
        }
    }

    var sectionTracking: CGFloat {
        switch self {
        case .standard: return 0.9
        case .neon: return 1.45
        case .nightBar: return 1.2
        }
    }

    func tabFont(isSelected: Bool) -> Font {
        switch self {
        case .standard:
            return .system(size: 13, weight: isSelected ? .semibold : .medium)
        case .neon:
            return .system(size: 11, weight: isSelected ? .bold : .semibold, design: .monospaced)
        case .nightBar:
            return .system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded)
        }
    }

    var metricLabelFont: Font {
        switch self {
        case .standard: return .system(size: 12, weight: .medium, design: .monospaced)
        case .neon: return .system(size: 11, weight: .bold, design: .monospaced)
        case .nightBar: return .system(size: 11, weight: .semibold, design: .rounded)
        }
    }

    var metricValueFont: Font {
        switch self {
        case .standard: return .system(size: 16, weight: .bold, design: .rounded)
        case .neon: return .system(size: 16, weight: .bold, design: .monospaced)
        case .nightBar: return .system(size: 16, weight: .bold, design: .rounded)
        }
    }

    var compactLabelFont: Font {
        switch self {
        case .standard: return .system(size: 10, weight: .medium, design: .monospaced)
        case .neon: return .system(size: 9, weight: .bold, design: .monospaced)
        case .nightBar: return .system(size: 9, weight: .semibold, design: .rounded)
        }
    }

    var compactValueFont: Font {
        switch self {
        case .standard: return .system(size: 11, weight: .medium, design: .monospaced)
        case .neon: return .system(size: 11, weight: .semibold, design: .monospaced)
        case .nightBar: return .system(size: 11, weight: .semibold, design: .monospaced)
        }
    }

    var bodyFont: Font {
        switch self {
        case .standard: return .system(size: 11, weight: .medium, design: .rounded)
        case .neon: return .system(size: 10, weight: .medium, design: .monospaced)
        case .nightBar: return .system(size: 10, weight: .medium, design: .rounded)
        }
    }

    var heroValueFont: Font {
        switch self {
        case .standard: return .system(size: 34, weight: .bold, design: .rounded)
        case .neon: return .system(size: 32, weight: .black, design: .monospaced)
        case .nightBar: return .system(size: 36, weight: .heavy, design: .rounded)
        }
    }

    var heroUnitFont: Font {
        switch self {
        case .standard: return .system(size: 13, weight: .medium, design: .rounded)
        case .neon: return .system(size: 11, weight: .bold, design: .monospaced)
        case .nightBar: return .system(size: 12, weight: .semibold, design: .rounded)
        }
    }

    var heroCaptionFont: Font {
        switch self {
        case .standard: return .system(size: 13, weight: .semibold)
        case .neon: return .system(size: 10, weight: .bold, design: .monospaced)
        case .nightBar: return .system(size: 11, weight: .bold, design: .rounded)
        }
    }

    var tabCornerRadius: CGFloat {
        switch self {
        case .standard: return 100
        case .neon: return 5
        case .nightBar: return 14
        }
    }

    var tabHorizontalPadding: CGFloat {
        switch self {
        case .standard: return 20
        case .neon: return 18
        case .nightBar: return 19
        }
    }

    var tabVerticalPadding: CGFloat {
        switch self {
        case .standard: return 6
        case .neon, .nightBar: return 7
        }
    }

    var surfaceCornerRadius: CGFloat {
        switch self {
        case .standard: return 12
        case .neon: return 7
        case .nightBar: return 14
        }
    }

    var surfaceStrokeWidth: CGFloat {
        switch self {
        case .standard: return 0.5
        case .neon: return 0.8
        case .nightBar: return 0.7
        }
    }

    var coreCornerRadius: CGFloat {
        switch self {
        case .standard: return 2
        case .neon: return 1
        case .nightBar: return 4
        }
    }

    var sparklineWidth: CGFloat {
        switch self {
        case .standard: return 1.5
        case .neon: return 1.8
        case .nightBar: return 2
        }
    }

    var textGlowRadius: CGFloat {
        switch self {
        case .standard: return 0
        case .neon: return 4
        case .nightBar: return 3
        }
    }

    var signalGlowRadius: CGFloat {
        switch self {
        case .standard: return 0
        case .neon: return 3
        case .nightBar: return 4
        }
    }
}

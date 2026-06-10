import SwiftUI

struct OverviewTabView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.appTheme) private var theme

    var body: some View {
        switch settings.appearancePreset.layout.overviewStyle {
        case .cards:
            ClassicOverviewView()
        case .compactGrid:
            CompactOverviewView()
        case .terminalRows:
            TerminalOverviewView()
        case .glassCards:
            GlassOverviewView()
        }
    }
}

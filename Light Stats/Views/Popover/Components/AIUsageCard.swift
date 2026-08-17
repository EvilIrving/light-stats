//
//  AIUsageCard.swift
//  Light Stats
//
//  Compact AI provider rows for the instrument readout (no card chrome).
//

import SwiftUI

// MARK: - Window Row

private struct WindowRow: View {
    @Environment(\.theme) private var theme

    let window: UsageWindow
    let useFlatColors: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(theme.chromeStyle.compactLabelFont)
                .foregroundStyle(theme.inkMuted)
                .frame(width: 22, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(
                        cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
                    )
                    .fill(theme.wellFill)
                    RoundedRectangle(
                        cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
                    )
                    .fill(useFlatColors ? theme.inkPrimary.opacity(0.4) : colorForRemaining(remainingPercent))
                    .frame(width: max(4, geo.size.width * min(remainingPercent, 100) / 100))
                }
            }
            .frame(height: 5)

            Text(String(format: "%.0f%%", remainingPercent))
                .font(
                    useFlatColors
                        ? .system(size: 11, weight: .regular, design: .monospaced)
                        : theme.chromeStyle.compactValueFont
                )
                .foregroundStyle(useFlatColors ? theme.inkPrimary : colorForRemaining(remainingPercent))
                .frame(width: 36, alignment: .trailing)

            Text(resetText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.inkMuted)
                .frame(width: 76, alignment: .trailing)
                .lineLimit(1)
        }
    }

    private var resetText: String {
        guard let resetsAt = window.resetsAt else { return "" }
        let remaining = resetsAt.timeIntervalSinceNow
        guard remaining > 0 else { return "" }
        let totalMinutes = Int(remaining) / 60
        if totalMinutes >= 1440 {
            return "\(totalMinutes / 1440)d \(totalMinutes % 1440 / 60)h"
        } else if totalMinutes >= 60 {
            return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
        } else {
            return "\(max(totalMinutes, 1))m"
        }
    }

    private var remainingPercent: Double {
        max(0, 100 - window.usedPercent)
    }

    private func colorForRemaining(_ remaining: Double) -> Color {
        if remaining > 25 {
            return theme.signalGood
        } else if remaining > 10 {
            return theme.signalWarn
        } else {
            return theme.signalBad
        }
    }
}

// MARK: - Compact Provider Row

/// A single provider's state as a compact row group (no card wrapper).
struct AIProviderCompactRow: View {
    @Environment(\.theme) private var theme

    let provider: AIProvider
    let state: ProviderFetchState
    let useFlatColors: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(assetIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                Text(provider.displayName)
                    .font(theme.chromeStyle.compactLabelFont)
                    .foregroundStyle(theme.inkSecondary)
                Spacer()
            }

            switch state {
            case .idle:
                Text("aiUsage.fetching".localized)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkMuted)

            case .loaded(let snapshot):
                VStack(spacing: 6) {
                    ForEach(snapshot.windows, id: \.label) { window in
                        WindowRow(window: window, useFlatColors: useFlatColors)
                    }
                }

            case .error(let error):
                Text(errorText(error))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func errorText(_ error: AIUsageError) -> String {
        let cli = providerCLIName
        switch error {
        case .tokenExpired:
            return "aiUsage.tokenExpired".localized(cli)
        case .credentialsMissing:
            return "aiUsage.credentialsMissing".localized(cli)
        case .network, .decoding, .endpointNotFound:
            return "aiUsage.fetchFailed".localized
        }
    }

    private var providerCLIName: String {
        switch provider {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        }
    }

    private var assetIconName: String {
        switch provider {
        case .claude: return "claudeLogo"
        case .codex: return "codexLogo"
        case .gemini: return "geminiLogo"
        }
    }
}

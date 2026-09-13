//
//  AIUsageCard.swift
//  Light Stats
//
//  Compact AI provider rows for the instrument readout (no card chrome).
//

import AppKit
import SwiftUI

// MARK: - Window Row

private struct WindowRow: View {
    @Environment(\.theme) private var theme

    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            // `label` is a `UsageWindowLabel` key, or a provider literal (`5h`, `Pro`).
            // Unknown keys resolve to themselves, so both render the same way.
            Text(window.label.localized)
                .font(theme.chromeStyle.compactLabelFont)
                .foregroundStyle(theme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(
                        cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
                    )
                    .fill(theme.wellFill)
                    if let remainingPercent {
                        RoundedRectangle(
                            cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
                        )
                        .fill(colorForRemaining(remainingPercent))
                        .frame(width: max(4, geo.size.width * min(remainingPercent, 100) / 100))
                    }
                }
            }
            .frame(height: 5)

            Text(remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(remainingPercent.map(colorForRemaining) ?? theme.inkMuted)
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

    private var remainingPercent: Double? {
        guard let used = window.usedPercent else { return nil }
        return max(0, 100 - used)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                providerIcon
                    .frame(width: 11, height: 11)
                Text(catalogRow?.displayName ?? provider.rawValue)
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
                        WindowRow(window: window)
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

    private var catalogRow: AIUsageProviderRow? {
        AIUsageCatalog.row(for: provider)
    }

    @ViewBuilder
    private var providerIcon: some View {
        ProviderIcon(catalogRow: catalogRow)
    }

    private func errorText(_ error: AIUsageError) -> String {
        if catalogRow?.credential == .apiToken {
            switch error {
            case .tokenExpired:
                return "aiUsage.tokenExpired.token".localized
            case .credentialsMissing:
                return "aiUsage.credentialsMissing.token".localized
            case .network, .decoding, .endpointNotFound:
                return "aiUsage.fetchFailed".localized
            }
        }
        if catalogRow?.credential == .ideDatabase {
            let app = catalogRow?.cliName ?? provider.rawValue
            switch error {
            case .tokenExpired:
                return "aiUsage.tokenExpired.app".localized(app)
            case .credentialsMissing:
                return "aiUsage.credentialsMissing.app".localized(app)
            case .network, .decoding, .endpointNotFound:
                return "aiUsage.fetchFailed".localized
            }
        }
        let cli = catalogRow?.cliName ?? provider.rawValue
        switch error {
        case .tokenExpired:
            return "aiUsage.tokenExpired".localized(cli)
        case .credentialsMissing:
            return "aiUsage.credentialsMissing".localized(cli)
        case .network, .decoding, .endpointNotFound:
            return "aiUsage.fetchFailed".localized
        }
    }
}

// MARK: - Balance Grid Cell

/// Prepaid-balance providers (DeepSeek / Z.ai / OpenRouter) as side-by-side cells:
/// icon + name on top, the total balance below. No granted/topped-up breakdown.
struct BalanceCell: View {
    @Environment(\.theme) private var theme

    let provider: AIProvider
    let state: ProviderFetchState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                ProviderIcon(catalogRow: catalogRow)
                    .frame(width: 11, height: 11)
                Text(catalogRow?.displayName ?? provider.rawValue)
                    .font(theme.chromeStyle.compactLabelFont)
                    .foregroundStyle(theme.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(valueText)
                .font(theme.chromeStyle.compactValueFont)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private var catalogRow: AIUsageProviderRow? {
        AIUsageCatalog.row(for: provider)
    }

    private var valueText: String {
        switch state {
        case .idle:
            return "…"
        case .loaded(let snapshot):
            guard let balance = snapshot.balance else { return "—" }
            return "\(balance.currency) \(balance.total)"
        case .error:
            return "aiUsage.fetchFailed".localized
        }
    }

    private var valueColor: Color {
        switch state {
        case .idle, .error:
            return theme.inkMuted
        case .loaded(let snapshot):
            guard let balance = snapshot.balance, balance.isAvailable else {
                return theme.inkMuted
            }
            return theme.inkPrimary
        }
    }
}

private struct ProviderIcon: View {
    let catalogRow: AIUsageProviderRow?

    var body: some View {
        let name = catalogRow?.iconAssetName ?? ""
        if NSImage(named: name) != nil {
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: catalogRow?.symbolFallback ?? "sparkles")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

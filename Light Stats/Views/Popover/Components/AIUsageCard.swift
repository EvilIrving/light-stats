//
//  AIUsageCard.swift
//  Light Stats
//
//  Compact AI provider rows for the instrument readout (no card chrome).
//

import AppKit
import SwiftUI

// MARK: - Quota meter

/// Remaining-quota track + percent (or “No limit”) + reset countdown.
/// Never synthesizes a bar from a balance.
private struct QuotaMeter: View {
    @Environment(\.theme) private var theme

    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            if let remainingPercent {
                progressTrack(remainingPercent)
                Text(String(format: "%.0f%%", remainingPercent))
                    .font(theme.chromeStyle.compactValueFont)
                    .foregroundStyle(colorForRemaining(remainingPercent))
                    .frame(width: 36, alignment: .trailing)
            } else {
                Text("aiUsage.noLimit".localized)
                    .font(theme.chromeStyle.compactValueFont)
                    .foregroundStyle(theme.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Text(resetText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.inkMuted)
                .frame(width: 56, alignment: .trailing)
                .lineLimit(1)
        }
    }

    private func progressTrack(_ remainingPercent: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(
                    cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
                )
                .fill(theme.wellFill)
                RoundedRectangle(
                    cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
                )
                .fill(colorForRemaining(remainingPercent))
                .frame(width: max(4, geo.size.width * min(remainingPercent, 100) / 100))
            }
        }
        .frame(height: 5)
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

// MARK: - Expanded period row

private struct WindowRow: View {
    @Environment(\.theme) private var theme

    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label.localized)
                .font(theme.chromeStyle.compactLabelFont)
                .foregroundStyle(theme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 36, alignment: .leading)
            QuotaMeter(window: window)
        }
        .padding(.leading, 15)
    }
}

// MARK: - Compact Provider Row

/// A single provider as one compact header line; extra windows appear only
/// after expand.
struct AIProviderCompactRow: View {
    @Environment(\.theme) private var theme
    @State private var isExpanded = false

    let provider: AIProvider
    let state: ProviderFetchState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            expandedWindows
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggleExpanded)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(canExpand ? .isButton : [])
        .accessibilityHint(expandHint)
    }

    private var headerLine: some View {
        HStack(spacing: 8) {
            identity
            headerTrailing
            if canExpand {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.inkSecondary)
                    .frame(width: 10, height: 10)
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 4) {
            providerIcon
                .frame(width: 11, height: 11)
            Text(providerName)
                .font(theme.chromeStyle.compactLabelFont)
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 56, maxWidth: 96, alignment: .leading)
        .layoutPriority(1)
    }

    @ViewBuilder
    private var headerTrailing: some View {
        switch state {
        case .idle:
            statusText("aiUsage.fetching".localized)

        case .error(let error):
            statusText(errorText(error))

        case .loaded(let snapshot):
            loadedHeaderTrailing(snapshot)
        }
    }

    @ViewBuilder
    private func loadedHeaderTrailing(_ snapshot: ProviderUsageSnapshot) -> some View {
        if isExpanded {
            headerBalance(snapshot.balance)
        } else if let primary = AIUsageWindowPicker.nearestReset(in: snapshot.windows) {
            QuotaMeter(window: primary)
        } else {
            headerBalance(snapshot.balance)
        }
    }

    @ViewBuilder
    private func headerBalance(_ balance: UsageBalance?) -> some View {
        Spacer(minLength: 8)
        if let balance {
            BalanceRow(balance: balance)
        }
    }

    @ViewBuilder
    private var expandedWindows: some View {
        if let snapshot = loadedSnapshot {
            let windows = AIUsageWindowPicker.detailWindows(
                in: snapshot.windows,
                expanded: isExpanded
            )
            if !windows.isEmpty {
                VStack(spacing: 6) {
                    ForEach(windows, id: \.self) { window in
                        WindowRow(window: window)
                    }
                }
            }
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(theme.inkMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerName: String {
        catalogRow?.displayName ?? provider.rawValue
    }

    private var catalogRow: AIUsageProviderRow? {
        AIUsageCatalog.row(for: provider)
    }

    private var loadedSnapshot: ProviderUsageSnapshot? {
        state.snapshot
    }

    private var canExpand: Bool {
        (loadedSnapshot?.windows.count ?? 0) > 1
    }

    private var expandHint: String {
        guard canExpand else { return "" }
        return isExpanded
            ? "aiUsage.collapseWindows".localized
            : "aiUsage.expandWindows".localized
    }

    private func toggleExpanded() {
        guard canExpand else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            isExpanded.toggle()
        }
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

// MARK: - Balance Row

/// Prepaid-balance amount only. Never reads `usedPercent` or draws a bar.
struct BalanceRow: View {
    @Environment(\.theme) private var theme

    let balance: UsageBalance

    var body: some View {
        Text("\(balance.currency) \(balance.total)")
            .font(theme.chromeStyle.compactValueFont)
            .foregroundStyle(balance.isAvailable ? theme.inkPrimary : theme.inkMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct ProviderIcon: View {
    let catalogRow: AIUsageProviderRow?

    var body: some View {
        let name = catalogRow?.iconAssetName ?? ""
        if NSImage(named: name) != nil {
            Image(name)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: catalogRow?.symbolFallback ?? "sparkles")
                .resizable()
                .scaledToFit()
        }
    }
}

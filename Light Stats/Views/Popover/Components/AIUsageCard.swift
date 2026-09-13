//
//  AIUsageCard.swift
//  Light Stats
//
//  Compact AI provider rows for the instrument readout (no card chrome).
//

import AppKit
import SwiftUI

// MARK: - Headroom cabin

/// Remaining-headroom meter + percent (or “No limit”) + reset countdown.
/// Fill is space left, never a synthesized balance bar.
private struct HeadroomCabin: View {
    @Environment(\.theme) private var theme

    let window: UsageWindow
    var showsPeriodChip: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Text(window.label.localized)
                .font(theme.chromeStyle.compactLabelFont)
                .foregroundStyle(theme.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: showsPeriodChip ? 36 : 0, alignment: .leading)
                .padding(.trailing, showsPeriodChip ? 8 : 0)
                .opacity(showsPeriodChip ? 1 : 0)
                .clipped()

            if let remainingPercent {
                headroomTrack(remainingPercent)
                Text(String(format: "%.0f%%", remainingPercent))
                    .font(theme.chromeStyle.compactValueFont)
                    .foregroundStyle(colorForRemaining(remainingPercent))
                    .frame(width: 36, alignment: .trailing)
                    .padding(.leading, 8)
            } else {
                Text("aiUsage.noLimit".localized)
                    .font(theme.chromeStyle.compactValueFont)
                    .foregroundStyle(theme.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.leading, 8)
            }

            Text(resetText)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(theme.inkMuted)
                .frame(width: 56, alignment: .trailing)
                .padding(.leading, 8)
                .lineLimit(1)
        }
    }

    private func headroomTrack(_ remainingPercent: Double) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(
                cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
            )
            .fill(theme.wellFill)
            RoundedRectangle(
                cornerRadius: theme.chromeStyle.usesNightBarTreatment ? 2.5 : 100
            )
            .fill(colorForRemaining(remainingPercent))
            .scaleEffect(x: max(0.04, min(remainingPercent, 100) / 100), y: 1, anchor: .leading)
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

// MARK: - Compact Provider Row

/// A single provider as one compact header line; extra windows appear only
/// after expand. The hero cabin uses matched geometry so it rides down/up.
struct AIProviderCompactRow: View {
    private static let cabinEffectID = "headroomCabin"
    private static let identityWidth: CGFloat = 96
    private static let cabinMotion = Animation.easeInOut(duration: 0.3)

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cabinNamespace
    @State private var isExpanded = false

    let provider: AIProvider
    let state: ProviderFetchState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerLine
            expandedCabins
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
        .frame(minHeight: 14)
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
        .frame(width: Self.identityWidth, alignment: .leading)
        .transaction { transaction in
            transaction.animation = nil
        }
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
        } else if let primary = AIUsageWindowPicker.mostStrained(in: snapshot.windows) {
            heroCabin(primary, showsPeriodChip: false)
        } else {
            headerBalance(snapshot.balance)
        }
    }

    @ViewBuilder
    private func headerBalance(_ balance: UsageBalance?) -> some View {
        Spacer(minLength: 8)
        if let balance {
            BalanceRow(balance: balance)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var expandedCabins: some View {
        if isExpanded, let snapshot = loadedSnapshot {
            expandedCabinList(snapshot)
        }
    }

    @ViewBuilder
    private func expandedCabinList(_ snapshot: ProviderUsageSnapshot) -> some View {
        let hero = AIUsageWindowPicker.mostStrained(in: snapshot.windows)
        let others = AIUsageWindowPicker.supportingWindows(in: snapshot.windows)
        VStack(alignment: .leading, spacing: 6) {
            if let hero {
                heroCabin(hero, showsPeriodChip: true)
            }
            ForEach(others, id: \.label) { window in
                HeadroomCabin(window: window, showsPeriodChip: true)
                    .transition(
                        .opacity.combined(with: .offset(y: reduceMotion ? 0 : -8))
                    )
            }
        }
        .transition(.identity)
    }

    @ViewBuilder
    private func heroCabin(_ window: UsageWindow, showsPeriodChip: Bool) -> some View {
        let cabin = HeadroomCabin(window: window, showsPeriodChip: showsPeriodChip)
        if reduceMotion {
            cabin
        } else {
            cabin.matchedGeometryEffect(
                id: Self.cabinEffectID,
                in: cabinNamespace,
                properties: .frame,
                anchor: .topLeading
            )
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
        if reduceMotion {
            isExpanded.toggle()
        } else {
            withAnimation(Self.cabinMotion) {
                isExpanded.toggle()
            }
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

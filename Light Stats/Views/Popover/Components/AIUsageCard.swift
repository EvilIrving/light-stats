//
//  AIUsageCard.swift
//  Light Stats
//
//  Created on 2026/06/10.
//
//  Logic chain — card display states:
//
//  ┌─ .idle ──────────────────────────────────────────────────┐
//  │  "Fetching…" placeholder. Shown before the first fetch.  │
//  │  The app never shows stale/last-session data.            │
//  └──────────────────────────────────────────────────────────┘
//                           │ (fetch completes)
//  ┌─ .loaded(snapshot) ─────────────────────────────────────┐
//  │  WindowRow × N — progress bar + remaining% + reset time │
//  │  Colors: green (>25%) / yellow (>10%) / red (≤10%)      │
//  │  Flat mode: monochrome bars, no semantic color.         │
//  └──────────────────────────────────────────────────────────┘
//                           │ (credentials missing / logged out)
//  ┌─ .error(AIUsageError) ──────────────────────────────────┐
//  │  Error text only.                                       │
//  └──────────────────────────────────────────────────────────┘
//

import SwiftUI

/// Overview card showing one AI provider's subscription usage windows.
struct AIUsageCard: View {
    let provider: AIProvider
    let state: ProviderFetchState
    let useFlatColors: Bool

    var body: some View {
        BentoCard(title: provider.displayName, icon: symbolIcon, assetIcon: assetIcon) {
            switch state {
            case .idle:
                Text("aiUsage.fetching".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)

            case .loaded(let snapshot):
                windowsView(snapshot)

            case .error(let error):
                Text(errorText(error))
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var assetIcon: String? {
        switch provider {
        case .claude: return "claudeLogo"
        case .codex: return "codexLogo"
        case .gemini: return "geminiLogo"
        }
    }

    private var symbolIcon: String? { nil }

    // MARK: - Windows

    private func windowsView(_ snapshot: ProviderUsageSnapshot) -> some View {
        VStack(spacing: 6) {
            ForEach(snapshot.windows, id: \.label) { window in
                WindowRow(window: window, useFlatColors: useFlatColors)
            }
        }
    }

    // MARK: - Texts

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
}

// MARK: - Window Row

private struct WindowRow: View {
    let window: UsageWindow
    let useFlatColors: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.labelMuted)
                .frame(width: 22, alignment: .leading)

            // Progress bar (remaining)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(useFlatColors ? Color.primary.opacity(0.4) : colorForRemaining(remainingPercent))
                        .frame(width: max(4, geo.size.width * min(remainingPercent, 100) / 100))
                }
            }
            .frame(height: 5)

            Text(String(format: "%.0f%%", remainingPercent))
                .font(.system(size: 11, weight: useFlatColors ? .regular : .semibold, design: .monospaced))
                .foregroundColor(useFlatColors ? .primary : colorForRemaining(remainingPercent))
                .frame(width: 36, alignment: .trailing)

            Text(resetText)
                .font(.system(size: 9))
                .foregroundColor(.labelMuted)
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
            return .green
        } else if remaining > 10 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Compact Provider Row (for consolidated AI Usage card)

/// A single provider's state rendered as a compact row group (no BentoCard wrapper).
/// Shows the provider logo + name as a header, then its usage windows underneath.
struct AIProviderCompactRow: View {
    let provider: AIProvider
    let state: ProviderFetchState
    let useFlatColors: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Provider header
            HStack(spacing: 4) {
                Image(provider.assetIconName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 11, height: 11)
                Text(provider.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            // Provider content
            switch state {
            case .idle:
                Text("aiUsage.fetching".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
                    .padding(.leading, 15)

            case .loaded(let snapshot):
                windowsRows(snapshot)

            case .error(let error):
                Text(AIProviderCompactRow.errorText(error, cli: providerCLIName))
                    .font(.system(size: 10))
                    .foregroundColor(.labelMuted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 15)
            }
        }
    }

    private func windowsRows(_ snapshot: ProviderUsageSnapshot) -> some View {
        VStack(spacing: 4) {
            ForEach(snapshot.windows, id: \.label) { window in
                WindowRow(window: window, useFlatColors: useFlatColors)
            }
        }
        .padding(.leading, 15)
    }

    private var providerCLIName: String {
        switch provider {
        case .claude: return "claude"
        case .codex: return "codex"
        case .gemini: return "gemini"
        }
    }

    static func errorText(_ error: AIUsageError, cli: String) -> String {
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

private extension AIProvider {
    var assetIconName: String {
        switch self {
        case .claude: return "claudeLogo"
        case .codex: return "codexLogo"
        case .gemini: return "geminiLogo"
        }
    }
}

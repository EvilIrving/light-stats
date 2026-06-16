//
//  AIUsageCard.swift
//  Light Stats
//
//  Created on 2026/06/10.
//

import SwiftUI

/// Overview card showing one AI provider's subscription usage windows.
struct AIUsageCard: View {
    let provider: AIProvider
    let state: ProviderFetchState
    let isRefreshing: Bool
    let useFlatColors: Bool
    let retry: () -> Void

    var body: some View {
        BentoCard(title: provider.displayName, icon: symbolIcon, assetIcon: assetIcon) {
            switch state {
            case .idle:
                Text("overview.loading".localized)
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)

            case .loaded(let snapshot):
                windowsView(snapshot)

            case .stale(let snapshot):
                VStack(alignment: .leading, spacing: 6) {
                    windowsView(snapshot)
                    Text("aiUsage.updatedAgo".localized(agoString(since: snapshot.fetchedAt)))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }

            case .error(let error):
                HStack(spacing: 8) {
                    Text(errorText(error))
                        .font(.system(size: 11))
                        .foregroundColor(.labelMuted)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    RetryButton(isRefreshing: isRefreshing, action: retry)
                }
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

    private var symbolIcon: String? {
        switch provider {
        case .claude, .codex, .gemini: return nil
        }
    }

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

    private func agoString(since date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date)) / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Retry Button

private struct RetryButton: View {
    let isRefreshing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            rotatingIcon
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.labelMuted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
    }

    @ViewBuilder
    private var rotatingIcon: some View {
        if isRefreshing {
            TimelineView(.animation) { context in
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
            }
        } else {
            Image(systemName: "arrow.clockwise")
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

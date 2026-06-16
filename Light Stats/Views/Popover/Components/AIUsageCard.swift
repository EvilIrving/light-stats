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

    var body: some View {
        BentoCard(title: provider.displayName, assetIcon: assetIcon) {
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
                Text(errorText(error))
                    .font(.system(size: 11))
                    .foregroundColor(.labelMuted)
                    .lineLimit(2)
            }
        }
    }

    private var assetIcon: String {
        switch provider {
        case .claude: return "claudeLogo"
        case .codex: return "codexLogo"
        }
    }

    // MARK: - Windows

    private func windowsView(_ snapshot: ProviderUsageSnapshot) -> some View {
        VStack(spacing: 6) {
            ForEach(snapshot.windows, id: \.label) { window in
                WindowRow(window: window)
            }
        }
    }

    // MARK: - Texts

    private func errorText(_ error: AIUsageError) -> String {
        let cli = provider == .claude ? "claude" : "codex"
        switch error {
        case .tokenExpired:
            return "aiUsage.tokenExpired".localized(cli)
        case .credentialsMissing:
            return "aiUsage.credentialsMissing".localized(cli)
        case .network, .decoding:
            return "aiUsage.fetchFailed".localized
        }
    }

    private func agoString(since date: Date) -> String {
        let minutes = max(0, Int(Date().timeIntervalSince(date)) / 60)
        if minutes < 60 { return "\(minutes)m" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

// MARK: - Window Row

private struct WindowRow: View {
    let window: UsageWindow

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
                        .fill(colorForRemaining(remainingPercent))
                        .frame(width: max(4, geo.size.width * min(remainingPercent, 100) / 100))
                }
            }
            .frame(height: 5)

            Text(String(format: "%.0f%%", remainingPercent))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(colorForRemaining(remainingPercent))
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

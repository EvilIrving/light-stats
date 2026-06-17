//
//  AIUsageCard.swift
//  Light Stats
//
//  Created on 2026/06/10.
//
//  Logic chain — card display states:
//
//  ┌─ .idle ──────────────────────────────────────────────────┐
//  │  "Loading…" placeholder. Shown before first fetch.       │
//  └──────────────────────────────────────────────────────────┘
//                           │ (fetch completes)
//  ┌─ .loaded(snapshot) ─────────────────────────────────────┐
//  │  WindowRow × N — progress bar + remaining% + reset time │
//  │  Colors: green (>25%) / yellow (>10%) / red (≤10%)      │
//  │  Flat mode: monochrome bars, no semantic color.         │
//  └──────────────────────────────────────────────────────────┘
//                           │ (subsequent fetch fails)
//  ┌─ .stale(snapshot) ──────────────────────────────────────┐
//  │  Same as .loaded + "Updated Xm ago" subtitle.            │
//  │  Keeps last good data visible for transient failures.   │
//  └──────────────────────────────────────────────────────────┘
//                           │ (credentials missing / token expired)
//  ┌─ .error(AIUsageError) ──────────────────────────────────┐
//  │  Red error text + RetryButton (↻ RefreshGlyph).         │
//  │  Tap retry → AIUsageMonitor.retry(provider).             │
//  └──────────────────────────────────────────────────────────┘
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
                RefreshGlyph()
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
            }
        } else {
            RefreshGlyph()
        }
    }
}

// MARK: - Refresh Glyph

/// A near-complete circular refresh icon: a ~300° ring with an arrowhead at its
/// open end. Unlike SF Symbol `arrow.clockwise` (a shorter open arc), the long
/// sweep reads as a continuous loop while spinning. Sized to fill its frame and
/// tinted via `foregroundColor`, so it drops in where an `Image` would.
private struct RefreshGlyph: View {
    /// Where the ring opens (and the arrowhead sits), in degrees. 0° = 3 o'clock.
    private let gapAngle: Double = -55
    /// How much of the circle the ring covers.
    private let sweep: Double = 300

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = side * 0.11
            let radius = (side - lineWidth * 2.4) / 2
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let start = Angle.degrees(gapAngle)
            let end = Angle.degrees(gapAngle + sweep)

            ZStack {
                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: start, endAngle: end, clockwise: false)
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

                arrowHead(center: center, radius: radius, lineWidth: lineWidth)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Filled triangle at the arc's open end, pointing along the sweep tangent.
    private func arrowHead(center: CGPoint, radius: CGFloat, lineWidth: CGFloat) -> some View {
        let tip = lineWidth * 1.7
        let angle = CGFloat(gapAngle * .pi / 180)
        let point = CGPoint(x: center.x + radius * cos(angle),
                            y: center.y + radius * sin(angle))
        // Tangent at the open end (sweep goes counter-clockwise in screen space).
        let tangent = angle - .pi / 2
        return Path { path in
            for offset in stride(from: 0.0, to: 2 * .pi, by: 2 * .pi / 3) {
                let a = tangent + CGFloat(offset)
                let p = CGPoint(x: point.x + tip * cos(a), y: point.y + tip * sin(a))
                if offset == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
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

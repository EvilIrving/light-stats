//
//  PanelChrome.swift
//  Light Stats
//
//  Instrument / spec-sheet layout primitives. Replaces the old bento-card grid:
//  continuous vertical readout, mono eyebrows, hairline rules — no floating cards.
//

import SwiftUI

// MARK: - Section

/// A labeled block in the popover readout. Eyebrow sits above content; no card chrome.
struct PanelSection<Content: View>: View {
    @Environment(\.theme) private var theme

    let title: String?
    let icon: String?
    let assetIcon: String?
    let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        assetIcon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.assetIcon = assetIcon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || icon != nil || assetIcon != nil {
                HStack(spacing: 5) {
                    if let assetIcon {
                        Image(assetIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.inkFaint)
                    }
                    if let title {
                        Text(title.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.9)
                            .foregroundStyle(theme.inkFaint)
                    }
                    Spacer(minLength: 0)
                }
            }
            content
        }
    }
}

// MARK: - Hairline

struct PanelDivider: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.lineHairline)
            .frame(height: 1)
            .padding(.vertical, 2)
    }
}

// MARK: - Metric row

/// Single readout line: label · optional sparkline · value. Spec-sheet row.
struct MetricRow<Value: View>: View {
    @Environment(\.theme) private var theme

    let label: String
    let icon: String?
    let trend: SparklineSeries?
    let value: Value

    init(
        label: String,
        icon: String? = nil,
        trend: SparklineSeries? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.icon = icon
        self.trend = trend
        self.value = value()
    }

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.inkSecondary)
                        .frame(width: 14)
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.inkSecondary)
            }
            .frame(width: 72, alignment: .leading)

            if let trend, trend.values.count > 1 {
                Sparkline(series: [trend])
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .opacity(0.55)
            } else {
                Spacer(minLength: 0)
            }

            value
                .frame(minWidth: 56, alignment: .trailing)
        }
        .frame(minHeight: 26)
    }
}

// MARK: - Key / value line

/// Secondary meta row (proxy, exit node, disk IO…). Label left, value right.
struct MetaRow: View {
    @Environment(\.theme) private var theme

    let icon: String?
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.inkFaint)
                    .frame(width: 12)
            }
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor ?? theme.inkPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Hero readout

/// Large primary number block (health score, battery %).
struct HeroReadout<Trailing: View>: View {
    @Environment(\.theme) private var theme

    let value: String
    let unit: String?
    let caption: String?
    let valueColor: Color
    let trailing: Trailing

    init(
        value: String,
        unit: String? = nil,
        caption: String? = nil,
        valueColor: Color,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.value = value
        self.unit = unit
        self.caption = caption
        self.valueColor = valueColor
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(valueColor)
            if let unit {
                Text(unit)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.inkMuted)
            }
            if let caption {
                Text(caption)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(valueColor)
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

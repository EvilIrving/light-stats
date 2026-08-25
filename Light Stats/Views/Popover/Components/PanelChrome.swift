//
//  PanelChrome.swift
//  Light Stats
//
//  Instrument / spec-sheet layout primitives: continuous vertical readout,
//  mono eyebrows, hairline rules — no floating cards.
//

import SwiftUI

// MARK: - Section

/// A labeled block in the popover readout. Eyebrow sits above content; no card chrome.
struct PanelSection<Content: View>: View {
    @Environment(\.theme) private var theme

    let title: String?
    let icon: String?
    let svgIcon: AppSVGIcon?
    let assetIcon: String?
    let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        svgIcon: AppSVGIcon? = nil,
        assetIcon: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.svgIcon = svgIcon
        self.assetIcon = assetIcon
        self.content = content()
    }

    var body: some View {
        let style = theme.chromeStyle
        VStack(alignment: .leading, spacing: 8) {
            if title != nil || icon != nil || svgIcon != nil || assetIcon != nil {
                HStack(spacing: 5) {
                    if let assetIcon {
                        Image(assetIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 11, height: 11)
                    } else if let svgIcon {
                        SVGIcon(svgIcon, size: 11)
                            .foregroundStyle(style.usesIlluminatedTreatment ? theme.accent : theme.inkFaint)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(style.usesIlluminatedTreatment ? theme.accent : theme.inkFaint)
                    }
                    if let title {
                        Text(title.uppercased())
                            .font(style.sectionTitleFont)
                            .tracking(style.sectionTracking)
                            .foregroundStyle(style.usesIlluminatedTreatment ? theme.accent : theme.inkFaint)
                            .shadow(
                                color: style.usesIlluminatedTreatment ? theme.accent.opacity(0.5) : .clear,
                                radius: style.textGlowRadius
                            )
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
        Group {
            if theme.chromeStyle.usesNightBarTreatment {
                LinearGradient(
                    colors: [
                        Color.clear,
                        theme.signalAccent.opacity(0.80),
                        theme.signalBad.opacity(0.44),
                        theme.signalGood.opacity(0.72),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .shadow(color: theme.signalAccent.opacity(0.54), radius: 3)
            } else {
                Rectangle().fill(theme.lineHairline)
            }
        }
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
    let svgIcon: AppSVGIcon?
    let trend: SparklineSeries?
    let value: Value

    init(
        label: String,
        icon: String? = nil,
        svgIcon: AppSVGIcon? = nil,
        trend: SparklineSeries? = nil,
        @ViewBuilder value: () -> Value
    ) {
        self.label = label
        self.icon = icon
        self.svgIcon = svgIcon
        self.trend = trend
        self.value = value()
    }

    var body: some View {
        let style = theme.chromeStyle
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                if let svgIcon {
                    SVGIcon(svgIcon, size: 12)
                        .foregroundStyle(metricIconColor)
                        .shadow(
                            color: style.usesNightBarTreatment ? theme.signalInfo.opacity(0.55) : .clear,
                            radius: style.signalGlowRadius
                        )
                        .frame(width: 14)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(metricIconColor)
                        .shadow(
                            color: style.usesNightBarTreatment ? theme.signalInfo.opacity(0.55) : .clear,
                            radius: style.signalGlowRadius
                        )
                        .frame(width: 14)
                }
                Text(style.usesIlluminatedTreatment ? label.uppercased() : label)
                    .font(style.metricLabelFont)
                    .tracking(style.usesNeonTreatment ? 0.45 : style.usesNightBarTreatment ? 0.25 : 0)
                    .foregroundStyle(theme.inkSecondary)
            }
            .frame(width: 56, alignment: .leading)

            if let trend, trend.values.count > 1 {
                Sparkline(series: [trend])
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .opacity(0.55)
            } else {
                Spacer(minLength: 0)
            }

            value
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 26)
    }

    private var metricIconColor: Color {
        theme.metricIcon
    }
}

// MARK: - Key / value line

/// Secondary meta row (proxy, exit node, disk IO…). Label left, value right.
struct MetaRow: View {
    @Environment(\.theme) private var theme

    let icon: String?
    let svgIcon: AppSVGIcon?
    let label: String
    let value: String
    var valueColor: Color?

    init(
        icon: String? = nil,
        svgIcon: AppSVGIcon? = nil,
        label: String,
        value: String,
        valueColor: Color? = nil
    ) {
        self.icon = icon
        self.svgIcon = svgIcon
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        HStack(spacing: 6) {
            if let svgIcon {
                SVGIcon(svgIcon, size: 11)
                    .foregroundStyle(theme.inkFaint)
                    .frame(width: 12)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.inkFaint)
                    .frame(width: 12)
            }
            Text(theme.chromeStyle.usesIlluminatedTreatment ? label.uppercased() : label)
                .font(theme.chromeStyle.compactLabelFont)
                .tracking(theme.chromeStyle.usesNeonTreatment ? 0.35 : 0)
                .foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(theme.chromeStyle.compactValueFont)
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
        let style = theme.chromeStyle
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(value)
                .font(style.heroValueFont)
                .foregroundStyle(valueColor)
                .shadow(
                    color: style.usesNightBarTreatment ? valueColor.opacity(0.64) : .clear,
                    radius: style.usesNightBarTreatment ? style.signalGlowRadius + 1 : 0
                )
            if let unit {
                Text(unit)
                    .font(style.heroUnitFont)
                    .foregroundStyle(theme.inkMuted)
            }
            if let caption {
                Text(style.usesIlluminatedTreatment ? caption.uppercased() : caption)
                    .font(style.heroCaptionFont)
                    .tracking(style.usesNeonTreatment ? 0.55 : style.usesNightBarTreatment ? 0.25 : 0)
                    .foregroundStyle(valueColor)
                    .shadow(
                        color: style.usesIlluminatedTreatment ? valueColor.opacity(0.52) : .clear,
                        radius: style.signalGlowRadius
                    )
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

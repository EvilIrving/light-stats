//
//  QuickStatCard.swift
//  Light Stats
//
//  Compact metric tile for the Bento Grid theme (CPU / GPU / MEM / Load).
//

import SwiftUI

struct QuickStatCard<Value: View>: View {
    let title: String
    let icon: String?
    let svgIcon: AppSVGIcon?
    let height: CGFloat
    let trend: SparklineSeries?
    @ViewBuilder let value: () -> Value

    init(
        title: String,
        icon: String? = nil,
        svgIcon: AppSVGIcon? = nil,
        height: CGFloat,
        trend: SparklineSeries? = nil,
        @ViewBuilder value: @escaping () -> Value
    ) {
        self.title = title
        self.icon = icon
        self.svgIcon = svgIcon
        self.height = height
        self.trend = trend
        self.value = value
    }

    var body: some View {
        BentoCard(title: title, icon: icon, svgIcon: svgIcon, fixedHeight: height) {
            ZStack(alignment: .topLeading) {
                if let trend, trend.values.count > 1 {
                    Sparkline(series: [trend])
                        .opacity(0.35)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .allowsHitTesting(false)
                }
                value()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

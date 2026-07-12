//
//  QuickStatCard.swift
//  Light Stats
//
//  Compact metric tile for the Bento Grid theme (CPU / GPU / MEM / Load).
//

import SwiftUI

struct QuickStatCard<Value: View>: View {
    let title: String
    let icon: String
    let height: CGFloat
    let trend: SparklineSeries?
    @ViewBuilder let value: () -> Value

    var body: some View {
        BentoCard(title: title, icon: icon, fixedHeight: height) {
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

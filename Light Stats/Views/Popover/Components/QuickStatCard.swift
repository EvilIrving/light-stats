//
//  QuickStatCard.swift
//  Light Stats
//
//  Created on 2026/06/23.
//

import SwiftUI

/// 概览页四张紧凑指标卡（CPU/GPU/MEM/负载）的统一外壳：固定高度的 `BentoCard`，
/// 数值内容叠在一条淡淡的趋势折线之上。折线为可选——无历史数据时只显示数值。
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

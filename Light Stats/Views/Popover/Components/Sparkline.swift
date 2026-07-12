//
//  Sparkline.swift
//  Light Stats
//
//  Created on 2026/06/23.
//

import SwiftUI

/// 一条折线的数据：取值序列（从旧到新）+ 线色。
struct SparklineSeries {
    let values: [Double]
    let color: Color
}

/// 轻量趋势折线：把一条或多条等长时间序列归一化到统一纵轴后画成折线。
/// 多序列共享同一纵轴，方便直接比较（如网络上/下行）。纯 SwiftUI `Path`，
/// 不触碰 Core Graphics / Metal。线色来自 `SparklineSeries`（调用方应传 `theme` 信号色）。
struct Sparkline: View {
    @Environment(\.theme) private var theme

    let series: [SparklineSeries]
    var lineWidth: CGFloat = 1.5
    /// 仅单序列时在折线下方填充淡渐变；多序列时关闭以免叠色杂乱。
    private var showsFill: Bool { series.count == 1 }

    var body: some View {
        GeometryReader { geo in
            let bounds = valueBounds
            ZStack {
                // Subtle baseline so curves read against mesh / scrim.
                Path { path in
                    let y = geo.size.height * 0.5
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
                .stroke(theme.lineHairline.opacity(0.55), lineWidth: 0.5)

                ForEach(Array(series.enumerated()), id: \.offset) { _, line in
                    seriesView(line, in: geo.size, bounds: bounds)
                }
            }
        }
    }

    @ViewBuilder
    private func seriesView(_ line: SparklineSeries, in size: CGSize, bounds: ClosedRange<Double>) -> some View {
        let pts = points(line.values, in: size, bounds: bounds)
        let stroke = line.color
        if showsFill {
            areaPath(pts, height: size.height)
                .fill(LinearGradient(
                    colors: [stroke.opacity(0.32), stroke.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
        }
        linePath(pts)
            .stroke(stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }

    /// 全部序列合并后的取值范围；恒定序列退化为围绕该值的 ±1 区间避免除零。
    private var valueBounds: ClosedRange<Double> {
        let all = series.flatMap { $0.values }
        guard let lo = all.min(), let hi = all.max() else { return 0...1 }
        return lo == hi ? (lo - 1)...(hi + 1) : lo...hi
    }

    /// 把取值序列映射成绘图坐标点：x 均匀分布，y 按 `bounds` 归一化（顶部为大值）。
    private func points(_ values: [Double], in size: CGSize, bounds: ClosedRange<Double>) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let span = bounds.upperBound - bounds.lowerBound
        let inset = lineWidth
        let usableHeight = max(size.height - inset * 2, 1)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, value in
            let norm = span > 0 ? (value - bounds.lowerBound) / span : 0.5
            let y = inset + (1 - CGFloat(norm)) * usableHeight
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// 折线下方的封闭区域（用于渐变填充）：折线 + 沿底边闭合。
    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        var path = linePath(pts)
        guard let first = pts.first, let last = pts.last else { return path }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

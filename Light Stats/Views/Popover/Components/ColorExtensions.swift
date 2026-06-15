import SwiftUI

extension Color {
    /// 介于 .primary 和 .secondary 之间的中间色，
    /// 在 Liquid Glass 透明背景上比 .secondary 更易读，又不像 .primary 那么重。
    static let labelMuted: Color = .primary.opacity(0.9)
}

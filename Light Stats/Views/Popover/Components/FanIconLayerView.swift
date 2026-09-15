//
//  FanIconLayerView.swift
//  Light Stats
//

import AppKit
import SwiftUI

/// 弹窗里的风扇图标：旋转交给 `FanAnimationLayer` 在合成侧完成。
///
/// 之前的实现用 `TimelineView(.animation)` 逐帧累积角度：每次 tick 都会让整个弹窗
/// 视图树变脏，AppKit 随即对 hosting view 重做整体 layout（实测弹窗关着也照跑，
/// 主线程 36% 消耗在 `NSWindow layoutIfNeeded`）。图层旋转则完全不进 SwiftUI 图。
struct FanIconLayerView: NSViewRepresentable {
    /// 转速（RPM）。nil / 0 → 只显示静止图标。
    let rpm: Int?
    /// 宿主面板是否可见。不可见时图层停转并隐藏，不留下空转的动画。
    let isPanelVisible: Bool
    let tintColor: Color
    var pointSize: CGFloat = 13

    func makeNSView(context: Context) -> FanIconLayerHostView {
        FanIconLayerHostView()
    }

    func updateNSView(_ view: FanIconLayerHostView, context: Context) {
        view.apply(
            rpm: rpm,
            isPanelVisible: isPanelVisible,
            tintColor: tintColor,
            pointSize: pointSize
        )
    }
}

/// 承载 `FanAnimationLayer` 的薄壳：AppKit 负责尺寸与外观变化，SwiftUI 只下指令。
final class FanIconLayerHostView: NSView {

    private let fanLayer = FanAnimationLayer()
    private var rpm: Int?
    private var isPanelVisible = false
    private var tintColor: Color = .primary
    private var pointSize: CGFloat = 13

    override func makeBackingLayer() -> CALayer {
        fanLayer
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(rpm: Int?, isPanelVisible: Bool, tintColor: Color, pointSize: CGFloat) {
        self.rpm = rpm
        self.isPanelVisible = isPanelVisible
        self.tintColor = tintColor
        self.pointSize = pointSize
        syncFanLayer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncFanLayer()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncFanLayer()
    }

    /// 主题色可能是 `Color.secondary` 这类随外观解析的颜色，必须在当前外观下取 NSColor。
    private func resolvedTintColor() -> NSColor {
        var color = NSColor.black
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor(tintColor).usingColorSpace(.deviceRGB) ?? .black
        }
        return color
    }

    private func syncFanLayer() {
        fanLayer.iconPointSize = pointSize
        fanLayer.update(
            rpm: rpm,
            visible: isPanelVisible,
            contentsScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
            tintColor: resolvedTintColor()
        )
    }
}

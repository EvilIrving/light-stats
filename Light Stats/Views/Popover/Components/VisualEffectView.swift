import SwiftUI
import AppKit

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

/// Popover 背景：macOS 26 使用真正的 Liquid Glass（NSGlassEffectView），
/// 旧系统回退到传统 vibrancy 毛玻璃（NSVisualEffectView）。
struct GlassBackgroundView: NSViewRepresentable {
    var cornerRadius: CGFloat = 12
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        } else {
            let view = NSVisualEffectView()
            view.material = fallbackMaterial
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
    }
}

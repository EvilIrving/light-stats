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
        // NSGlassEffectView 仅存在于 macOS 26 SDK（Xcode 26 / Swift 6.2+）。
        // 用编译期守卫确保旧 SDK 也能构建，缺失时回退到传统 vibrancy 毛玻璃。
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            return glass
        }
        #endif
        let view = NSVisualEffectView()
        view.material = fallbackMaterial
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
        #endif
    }
}

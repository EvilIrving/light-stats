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

/// Popover / 窗口背景：macOS 26 使用真正的 Liquid Glass（NSGlassEffectView），
/// 旧系统回退到传统 vibrancy 毛玻璃（NSVisualEffectView）。
struct GlassBackgroundView: NSViewRepresentable {
    var cornerRadius: CGFloat = 12
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar
    /// 为 `true` 时把宿主 `NSWindow` 设为非透明，让 behind-window 玻璃/vibrancy
    /// 透出桌面。普通窗口（Settings / About / Update）默认是不透明的，必须这样配置
    /// 才能看到玻璃；NSPopover 天生非透明，所以 Popover/Toast 用默认 `false` 即可。
    var configuresWindow: Bool = false

    func makeNSView(context: Context) -> NSView {
        let effect = makeEffectView()
        guard configuresWindow else { return effect }
        // 包一层我们可控的容器，在它进入窗口层级后再配置宿主窗口透明——
        // 此时 `window` 已就绪，比在 makeNSView 里直接取 `window`（多半为 nil）可靠。
        let host = GlassHostView()
        effect.frame = host.bounds
        effect.autoresizingMask = [.width, .height]
        host.addSubview(effect)
        return host
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let effect = (nsView as? GlassHostView)?.subviews.first ?? nsView
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), let glass = effect as? NSGlassEffectView {
            glass.cornerRadius = cornerRadius
        }
        #endif
    }

    private func makeEffectView() -> NSView {
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
}

/// 玻璃背景容器：进入窗口层级后把宿主窗口设为非透明，使 behind-window 玻璃透出桌面。
private final class GlassHostView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
    }
}

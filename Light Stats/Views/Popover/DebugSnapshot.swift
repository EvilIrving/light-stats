//
//  DebugSnapshot.swift
//  Light Stats
//
//  临时调试入口：把面板各 Tab 的「完整内容」（不受 ScrollView 可见区域 / 滚动条裁剪）
//  渲染成 PNG 导出到 /tmp。仅 DEBUG 构建编译，正式包不含此代码。
//
//  实现：把内容放进一个离屏窗口里的真实 NSHostingView，给它一个超高的实体框架，
//  让内部 ScrollView 的内容完整铺开（不滚动），再用 cacheDisplay 抓真实图层——
//  这样玻璃背景（NSVisualEffectView）、App 图标等 AppKit 内容都能正确捕获，
//  避免 ImageRenderer 渲染不了这些内容的问题。
//
//  触发：面板标题栏的 DEBUG「相机」按钮，或按住 ⌥ Option 点击菜单栏图标。
//

#if DEBUG
import SwiftUI
import AppKit
import os

enum DebugSnapshot {
    private static let logger = AppLogger(subsystem: "com.lightstats.app", category: "DebugSnapshot")

    /// 面板内容固定宽度，与正式面板一致。
    private static let contentWidth: CGFloat = 360
    /// 足够高的画布，让内部 ScrollView 内容完整铺开、不触发滚动裁剪；
    /// 多出的部分会在导出时按实际内容裁掉。
    private static let canvasHeight: CGFloat = 3000

    /// 导出目录：项目根目录 docs/screenshots（目录不存在则自动创建）。
    private static var outputDirectory: URL {
        let sourceFile = URL(fileURLWithPath: #filePath)
        // DebugSnapshot.swift is at: .../macos-menus-stats/Light Stats/Views/Popover/DebugSnapshot.swift
        // Project root is 4 levels up from Popover
        let projectRoot = sourceFile
            .deletingLastPathComponent()  // Popover
            .deletingLastPathComponent()  // Views
            .deletingLastPathComponent()  // Light Stats
            .deletingLastPathComponent()  // macos-menus-stats
        let dir = projectRoot.appendingPathComponent("docs/screenshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 渲染所有 Tab 的完整内容到 /tmp，并在 Finder 中打开目录。
    @MainActor
    static func dumpPanel() {
        let monitor = SystemMonitor.shared
        let aiMonitor = AIUsageMonitor.shared

        let targets: [(name: String, view: AnyView)] = [
            ("popover-overview", AnyView(
                OverviewTabView()
                    .environmentObject(monitor)
                    .environmentObject(aiMonitor)
            )),
            ("popover-cleanup", AnyView(
                CleanupTabView()
                    .environmentObject(monitor)
                    .environmentObject(aiMonitor)
            ))
        ]

        // 跟随系统当前外观：深色给深底，浅色给浅底（玻璃无法离屏还原，用纯色替代）。
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bg = isDark
            ? Color(red: 0.17, green: 0.17, blue: 0.19)
            : Color(red: 0.95, green: 0.95, blue: 0.96)

        var firstURL: URL?
        for target in targets {
            let wrapped = target.view
                .frame(width: contentWidth, alignment: .top)
                .frame(width: contentWidth, height: canvasHeight, alignment: .top)
                .background(bg)

            if let url = capture(wrapped, name: target.name) {
                firstURL = firstURL ?? url
            }
        }

        if let url = firstURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            logger.info("Panel snapshot written to \(url.deletingLastPathComponent().path)")
        }
    }

    /// 离屏托管 + cacheDisplay 抓取，再按非透明内容裁去底部留白。
    @MainActor
    private static func capture<V: View>(_ view: V, name: String) -> URL? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: contentWidth, height: canvasHeight)

        // 放进离屏窗口，保证布局 / backing store 正常建立。
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.appearance = NSApp.effectiveAppearance
        window.setIsVisible(false)

        // 触发布局。
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let bounds = hosting.bounds
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds) else {
            logger.error("No bitmap rep: \(name)")
            return nil
        }
        hosting.cacheDisplay(in: bounds, to: rep)

        let trimmed = trimBottom(rep) ?? rep
        guard let png = trimmed.representation(using: .png, properties: [:]) else {
            logger.error("PNG encode failed: \(name)")
            return nil
        }

        let url = outputDirectory.appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
            logger.info("Wrote \(url.path)")
            return url
        } catch {
            logger.error("Write failed \(name): \(error.localizedDescription)")
            return nil
        }
    }

    /// 从底部往上扫描，裁掉与背景同色的留白，保留实际内容高度。
    private static func trimBottom(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0, h > 0 else { return nil }

        // 以左上角像素为背景基准色。
        guard let bg = rep.colorAt(x: 0, y: 0) else { return nil }
        let tolerance: CGFloat = 0.02

        var contentBottom = 0
        // 每隔几行采样，遇到与背景不同的行即记录。
        for y in stride(from: h - 1, through: 0, by: -1) {
            var rowHasContent = false
            for x in stride(from: 0, to: w, by: 8) {
                guard let c = rep.colorAt(x: x, y: y) else { continue }
                if abs(c.redComponent - bg.redComponent) > tolerance
                    || abs(c.greenComponent - bg.greenComponent) > tolerance
                    || abs(c.blueComponent - bg.blueComponent) > tolerance {
                    rowHasContent = true
                    break
                }
            }
            if rowHasContent {
                contentBottom = y
                break
            }
        }

        let pad = Int(16 * (rep.size.width > 0 ? CGFloat(w) / rep.size.width : 2))
        let croppedHeight = min(h, contentBottom + 1 + pad)
        guard croppedHeight > 0, croppedHeight < h,
              let cg = rep.cgImage,
              let sub = cg.cropping(to: CGRect(x: 0, y: 0, width: w, height: croppedHeight)) else {
            return nil
        }
        return NSBitmapImageRep(cgImage: sub)
    }
}
#endif

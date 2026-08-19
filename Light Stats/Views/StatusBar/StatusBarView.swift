//
//  StatusBarView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit
import QuartzCore

final class StatusBarView: NSView {

    // MARK: - Constants

    private enum Layout {
        static let logoWidth: CGFloat = 16
        static let percentItemWidth: CGFloat = 26  // CPU, GPU, MEM (e.g., "99%")
        static let diskItemWidth: CGFloat = 46     // DISK (e.g., "999 GB")
        static let networkItemWidth: CGFloat = 56  // NET (e.g., "↑0.0 KB/s" / "↓0.0 KB/s")
        // FAN: spinning icon, no number/label → fixed width regardless of RPM (no jitter).
        static let fanItemWidth: CGFloat = 22
        static let batteryItemWidth: CGFloat = 34  // BAT (e.g., "⚡100%")
        // HLT: 3-digit "100" ≈ 21.8pt @ valueFont; +~2.6pt padding/side (matches DISK).
        static let healthItemWidth: CGFloat = 27
        static let separatorWidth: CGFloat = 2
        static let itemHeight: CGFloat = 22
        static let arrowWidth: CGFloat = 8         // 箭头固定宽度
        static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        // Units (%, RPM, GB…) draw lighter than the number: regular weight, same size.
        static let unitFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        static let logoFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        // Network unit (KB/s…) draws lighter than the number, matching other stats.
        static let networkUnitFont = NSFont.systemFont(ofSize: 10, weight: .regular)
        static let unitAlpha: CGFloat = 0.7
    }

    // MARK: - Data

    private var displayItems: [DisplayItem] = []

    private struct DisplayItem {
        let value: String
        let label: String
        let width: CGFloat
        let isLogo: Bool
        let isNetwork: Bool
        let isFan: Bool

        init(
            value: String,
            label: String = "",
            width: CGFloat,
            isLogo: Bool,
            isNetwork: Bool = false,
            isFan: Bool = false
        ) {
            self.value = value
            self.label = label
            self.width = width
            self.isLogo = isLogo
            self.isNetwork = isNetwork
            self.isFan = isFan
        }
    }

    // MARK: - Fan animation state

    private let fanLayer = FanAnimationLayer()
    private var fanRPM: Int?

    // MARK: - Render target

    /// The status-item button we push the rendered template image to. Rendering as a
    /// template image (rather than drawing into this view directly) lets AppKit tint the
    /// content to match the *menu bar background*, not just the system light/dark setting —
    /// so text stays legible on a dark wallpaper-tinted menu bar, exactly like template icons.
    private weak var hostButton: NSButton?

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureFanLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureFanLayer()
    }

    /// This view is a transparent host: it renders the static template image into
    /// `button.image` and hosts the independently animated fan layer. Returning nil ensures it
    /// never intercepts clicks meant for the status-item button — all events pass through.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: - Public Methods

    func updateValues(
        cpu: Double,
        gpu: Double?,
        memory: Double,
        disk: UInt64,
        upload: Double,
        download: Double,
        fan: Int?,
        battery: BatteryInfo,
        health: HealthScore,
        settings: any SettingsManaging
    ) {
        displayItems.removeAll()

        // Logo
        if settings.showLogo {
            displayItems.append(DisplayItem(
                value: "◉",
                label: "",
                width: Layout.logoWidth,
                isLogo: true
            ))
        }

        // Health（默认关闭）：显示 0-100 总分。放在最前（Logo 之后、CPU 之前）。
        if settings.showHealth {
            displayItems.append(DisplayItem(
                value: "\(health.score)",
                label: "HLT",
                width: Layout.healthItemWidth,
                isLogo: false
            ))
        }

        // CPU
        if settings.showCPU {
            displayItems.append(DisplayItem(
                value: String(format: "%.0f%%", cpu),
                label: "CPU",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }

        // GPU
        if settings.showGPU {
            let gpuText = gpu.map { String(format: "%.0f%%", $0) } ?? "—"
            displayItems.append(DisplayItem(
                value: gpuText,
                label: "GPU",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }

        // Memory
        if settings.showMemory {
            displayItems.append(DisplayItem(
                value: String(format: "%.0f%%", memory),
                label: "MEM",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }

        // Disk
        if settings.showDisk {
            displayItems.append(DisplayItem(
                value: ByteFormatter.formatDisk(disk),
                label: "DISK",
                width: Layout.diskItemWidth,
                isLogo: false
            ))
        }

        // Network (上传在上，下载在下，字体相同间距紧凑)
        if settings.showNetwork {
            displayItems.append(DisplayItem(
                value: ByteFormatter.formatSpeed(upload),
                label: ByteFormatter.formatSpeed(download),
                width: Layout.networkItemWidth,
                isLogo: false,
                isNetwork: true
            ))
        }

        // Fan（独立 Core Animation 图层旋转，无数字/标签 → 固定宽度，不抖动）
        if settings.showFan {
            displayItems.append(DisplayItem(
                value: "",
                label: "",
                width: Layout.fanItemWidth,
                isLogo: false,
                isFan: true
            ))
            fanRPM = fan
        } else {
            fanRPM = nil
        }

        // Battery（充电/已充满前缀闪电；无电池显示横杠）
        if settings.showBattery {
            let batteryText: String
            switch battery.state {
            case .noBattery:
                batteryText = "—"
            case .charging, .charged:
                batteryText = "⚡\(Int(battery.percent.rounded()))%"
            case .acNotCharging, .discharging:
                batteryText = "\(Int(battery.percent.rounded()))%"
            }
            displayItems.append(DisplayItem(
                value: batteryText,
                label: "BAT",
                width: Layout.batteryItemWidth,
                isLogo: false
            ))
        }

        renderAndApply()
        syncFanLayer()
    }

    /// Connects the view to its status-item button and renders an initial image.
    func attach(to button: NSButton) {
        hostButton = button
        renderAndApply()
        syncFanLayer()
    }

    override func layout() {
        super.layout()
        syncFanLayerFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncFanLayer()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncFanLayer()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        syncFanLayerTint()
    }

    static func calculateWidth(settings: any SettingsManaging) -> CGFloat {
        var width: CGFloat = 0
        var itemCount = 0

        if settings.showLogo {
            width += Layout.logoWidth
            itemCount += 1
        }
        if settings.showCPU {
            width += Layout.percentItemWidth
            itemCount += 1
        }
        if settings.showGPU {
            width += Layout.percentItemWidth
            itemCount += 1
        }
        if settings.showMemory {
            width += Layout.percentItemWidth
            itemCount += 1
        }
        if settings.showDisk {
            width += Layout.diskItemWidth
            itemCount += 1
        }
        if settings.showNetwork {
            width += Layout.networkItemWidth
            itemCount += 1
        }
        if settings.showFan {
            width += Layout.fanItemWidth
            itemCount += 1
        }
        if settings.showBattery {
            width += Layout.batteryItemWidth
            itemCount += 1
        }
        if settings.showHealth {
            width += Layout.healthItemWidth
            itemCount += 1
        }

        // Add separator space between items
        if itemCount > 1 {
            width += CGFloat(itemCount - 1) * Layout.separatorWidth
        }

        return max(width, 20)  // Minimum width
    }

    // MARK: - Drawing

    /// Width of the rendered image, derived from the items (not the view frame) so it is
    /// independent of layout/autoresize timing.
    private var renderWidth: CGFloat {
        guard !displayItems.isEmpty else { return 20 }
        let items = displayItems.reduce(0) { $0 + $1.width }
        let separators = CGFloat(displayItems.count - 1) * Layout.separatorWidth
        return max(items + separators, 20)
    }

    /// Renders the current items into a template image and hands it to the button. AppKit
    /// then tints it to the menu-bar foreground colour (white on a dark bar, black on a light
    /// one), so text adapts identically to the logo/fan template icons.
    private func renderAndApply() {
        hostButton?.image = renderImage()
    }

    private func renderImage() -> NSImage {
        let size = NSSize(width: renderWidth, height: Layout.itemHeight)
        // Resolution-independent: AppKit invokes the drawing handler at the backing scale of
        // whichever display the menu bar is on, so the image stays crisp on Retina. The
        // deprecated `lockFocus()` baked a single scale at capture time and rendered soft when
        // the menu bar lived on a higher-scale display than the one focused at render.
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
            self?.drawContents(in: rect)
            return true
        }
        image.isTemplate = true  // alpha is the tint mask; preserves dimmed units/labels
        return image
    }

    private func drawContents(in bounds: NSRect) {
        // Opaque base colour: template tinting ignores RGB and keys off alpha, so the
        // de-emphasised units/labels keep their 0.7 alpha while the colour itself is replaced.
        let textColor = NSColor.black
        var xOffset: CGFloat = 0

        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)

            if item.isLogo {
                drawLogo(in: itemRect)
            } else if item.isFan {
                // The fan occupies a transparent slot here. Its contents are rendered by the
                // independently animated `fanLayer` below the static template image.
            } else if item.isNetwork {
                drawNetwork(item, in: itemRect, textColor: textColor)
            } else {
                drawStat(item, in: itemRect, textColor: textColor)
            }

            xOffset += item.width

            // Draw separator (except for the last item)
            if index < displayItems.count - 1 {
                xOffset += Layout.separatorWidth
            }
        }
    }

    /// Draws the app logo from Assets, template-tinted to the menu-bar colour.
    private func drawLogo(in itemRect: NSRect) {
        guard let image = NSImage(named: "StatusIcon") else { return }
        image.isTemplate = true  // Adapt to light/dark mode
        let iconSize: CGFloat = 16
        let iconRect = NSRect(
            x: itemRect.midX - iconSize / 2,
            y: itemRect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        image.draw(in: iconRect)
    }

    /// 网络项特殊绘制：箭头固定，数值等宽；单位（KB/s…）弱化为细体 + 淡灰，与其他项一致。
    private func drawNetwork(_ item: DisplayItem, in itemRect: NSRect, textColor: NSColor) {
        let arrowAttrs: [NSAttributedString.Key: Any] = [
            .font: Layout.networkFont,
            .foregroundColor: textColor
        ]
        let arrowXOffset: CGFloat = 2
        let globalYOffset: CGFloat = -1 // 整体下移 1 单位
        let valueX = itemRect.origin.x + arrowXOffset + Layout.arrowWidth

        // 上传 (上行)
        let upY = itemRect.midY + globalYOffset
        "↑".draw(at: NSPoint(x: itemRect.origin.x + arrowXOffset, y: upY), withAttributes: arrowAttrs)
        networkValue(item.value, textColor: textColor).draw(at: NSPoint(x: valueX, y: upY))

        // 下载 (下行)
        let textHeight = item.label.size(withAttributes: arrowAttrs).height
        let downY = itemRect.midY - textHeight + 1 + globalYOffset
        "↓".draw(at: NSPoint(x: itemRect.origin.x + arrowXOffset, y: downY), withAttributes: arrowAttrs)
        networkValue(item.label, textColor: textColor).draw(at: NSPoint(x: valueX, y: downY))
    }

    /// Builds a network speed string with the numeric part full-weight and the unit de-emphasised.
    private func networkValue(_ value: String, textColor: NSColor) -> NSAttributedString {
        let (number, unit) = Self.splitValue(value)
        let result = NSMutableAttributedString(
            string: number,
            attributes: [.font: Layout.networkFont, .foregroundColor: textColor]
        )
        if !unit.isEmpty {
            result.append(NSAttributedString(
                string: unit,
                attributes: [
                    .font: Layout.networkUnitFont,
                    .foregroundColor: textColor.withAlphaComponent(Layout.unitAlpha)
                ]
            ))
        }
        return result
    }

    /// Draws a value+label stat. The numeric part is emphasised (semibold, full colour);
    /// the trailing unit (%, RPM, GB…) is de-emphasised (regular weight, dimmer).
    private func drawStat(_ item: DisplayItem, in itemRect: NSRect, textColor: NSColor) {
        let (number, unit) = Self.splitValue(item.value)
        let value = NSMutableAttributedString(
            string: number,
            attributes: [.font: Layout.valueFont, .foregroundColor: textColor]
        )
        if !unit.isEmpty {
            value.append(NSAttributedString(
                string: unit,
                attributes: [.font: Layout.unitFont, .foregroundColor: textColor.withAlphaComponent(Layout.unitAlpha)]
            ))
        }
        let valueSize = value.size()
        value.draw(at: NSPoint(x: itemRect.midX - valueSize.width / 2, y: itemRect.height / 2 - 2))

        // Label (bottom) - clearer font, tighter spacing
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: Layout.labelFont,
            .foregroundColor: textColor.withAlphaComponent(Layout.unitAlpha)
        ]
        let labelSize = item.label.size(withAttributes: labelAttrs)
        let labelPoint = NSPoint(
            x: itemRect.midX - labelSize.width / 2,
            y: itemRect.height / 2 - labelSize.height - 2
        )
        item.label.draw(at: labelPoint, withAttributes: labelAttrs)
    }

    // MARK: - Fan layer

    func stopFanAnimation() {
        fanLayer.stop()
    }

    private func configureFanLayer() {
        wantsLayer = true
        layer?.addSublayer(fanLayer)
        fanLayer.isHidden = true
    }

    private func syncFanLayer() {
        syncFanLayerFrame()
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        fanLayer.update(
            rpm: fanRPM,
            visible: fanFrame != nil,
            contentsScale: scale,
            tintColor: resolvedFanTintColor()
        )
    }

    private func syncFanLayerFrame() {
        guard let fanFrame else {
            fanLayer.isHidden = true
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fanLayer.frame = fanFrame
        fanLayer.setNeedsLayout()
        fanLayer.layoutIfNeeded()
        CATransaction.commit()
    }

    private func syncFanLayerTint() {
        fanLayer.updateTint(resolvedFanTintColor())
    }

    private var fanFrame: NSRect? {
        var xOffset: CGFloat = 0
        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)
            if item.isFan {
                return itemRect
            }
            xOffset += item.width
            if index < displayItems.count - 1 {
                xOffset += Layout.separatorWidth
            }
        }
        return nil
    }

    private func resolvedFanTintColor() -> NSColor {
        let appearance = hostButton?.effectiveAppearance ?? effectiveAppearance
        var color = NSColor.black
        appearance.performAsCurrentDrawingAppearance {
            let tint = hostButton?.contentTintColor ?? NSColor.labelColor
            color = tint.usingColorSpace(.deviceRGB) ?? .black
        }
        return color
    }

    /// Splits a value like "2501 RPM" / "38%" / "⚡100%" into (number, unit).
    /// Leading digits, separators and the charging bolt stay with the number; the rest is the unit.
    /// A purely non-numeric value (e.g. "—") is returned whole as the number so it stays full-weight.
    private static func splitValue(_ value: String) -> (number: String, unit: String) {
        let numberChars: Set<Character> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", ",", "⚡"]
        guard let splitIdx = value.firstIndex(where: { !numberChars.contains($0) }),
              splitIdx != value.startIndex else {
            return (value, "")
        }
        return (String(value[..<splitIdx]), String(value[splitIdx...]))
    }
}

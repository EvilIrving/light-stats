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
        static let networkItemWidth: CGFloat = 62  // NET (3-sig-digit speeds, e.g. "12.3 MB/s")
        // FAN: spinning icon, no number/label → fixed width regardless of RPM (no jitter).
        static let fanItemWidth: CGFloat = 22
        static let batteryItemWidth: CGFloat = 34  // BAT (e.g., "⚡100%")
        // HLT: 3-digit "100" ≈ 21.8pt @ valueFont; +~2.6pt padding/side (matches DISK).
        static let healthItemWidth: CGFloat = 27
        /// Spacing when the optional visible divider is off.
        static let defaultSeparatorWidth: CGFloat = 2
        static let separatorLineWidth: CGFloat = 1
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
    private var separatorWidth: CGFloat = Layout.defaultSeparatorWidth
    private var drawsSeparator = false
    private var networkColorStyle: StatusBarNetworkColorStyle = .system

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

    struct Metrics {
        var cpu: Double
        var gpu: Double?
        var memory: Double
        var disk: UInt64
        var upload: Double
        var download: Double
        var fan: Int?
        var battery: BatteryInfo
        var health: HealthScore
        var hasFanHardware: Bool
        var hasBatteryHardware: Bool
    }

    func updateValues(metrics: Metrics, settings: any SettingsManaging) {
        applyChrome(settings)
        displayItems = makeDisplayItems(metrics: metrics, settings: settings)
        fanRPM = (settings.showFan && metrics.hasFanHardware) ? metrics.fan : nil
        renderAndApply()
        syncFanLayer()
    }

    private func applyChrome(_ settings: any SettingsManaging) {
        drawsSeparator = settings.showStatusBarSeparator
        separatorWidth = drawsSeparator
            ? CGFloat(settings.statusBarSeparatorWidth)
            : Layout.defaultSeparatorWidth
        networkColorStyle = settings.statusBarNetworkColorStyle
    }

    private func makeDisplayItems(
        metrics: Metrics,
        settings: any SettingsManaging
    ) -> [DisplayItem] {
        var items: [DisplayItem] = []
        if settings.showLogo {
            items.append(DisplayItem(value: "◉", width: Layout.logoWidth, isLogo: true))
        }
        // Network sits leftmost among metrics — widest slot, easiest to scan.
        if settings.showNetwork {
            items.append(DisplayItem(
                value: ByteFormatter.formatSpeedAligned(metrics.upload),
                label: ByteFormatter.formatSpeedAligned(metrics.download),
                width: Layout.networkItemWidth,
                isLogo: false,
                isNetwork: true
            ))
        }
        if settings.showHealth {
            items.append(DisplayItem(
                value: "\(metrics.health.score)",
                label: "HLT",
                width: Layout.healthItemWidth,
                isLogo: false
            ))
        }
        if settings.showCPU {
            items.append(DisplayItem(
                value: String(format: "%.0f%%", metrics.cpu),
                label: "CPU",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }
        if settings.showGPU {
            items.append(DisplayItem(
                value: metrics.gpu.map { String(format: "%.0f%%", $0) } ?? "—",
                label: "GPU",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }
        if settings.showMemory {
            items.append(DisplayItem(
                value: String(format: "%.0f%%", metrics.memory),
                label: "MEM",
                width: Layout.percentItemWidth,
                isLogo: false
            ))
        }
        if settings.showDisk {
            items.append(DisplayItem(
                value: ByteFormatter.formatDisk(metrics.disk),
                label: "DISK",
                width: Layout.diskItemWidth,
                isLogo: false
            ))
        }
        if settings.showFan && metrics.hasFanHardware {
            items.append(DisplayItem(
                value: "",
                width: Layout.fanItemWidth,
                isLogo: false,
                isFan: true
            ))
        }
        if settings.showBattery && metrics.hasBatteryHardware {
            items.append(DisplayItem(
                value: batteryText(metrics.battery),
                label: "BAT",
                width: Layout.batteryItemWidth,
                isLogo: false
            ))
        }
        return items
    }

    private func batteryText(_ battery: BatteryInfo) -> String {
        switch battery.state {
        case .noBattery:
            return "—"
        case .charging, .charged:
            return "⚡\(Int(battery.percent.rounded()))%"
        case .acNotCharging, .discharging:
            return "\(Int(battery.percent.rounded()))%"
        }
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

    static func calculateWidth(
        settings: any SettingsManaging,
        hasFanHardware: Bool,
        hasBatteryHardware: Bool
    ) -> CGFloat {
        var width: CGFloat = 0
        var itemCount = 0

        if settings.showLogo {
            width += Layout.logoWidth
            itemCount += 1
        }
        if settings.showNetwork {
            width += Layout.networkItemWidth
            itemCount += 1
        }
        if settings.showHealth {
            width += Layout.healthItemWidth
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
        if settings.showFan && hasFanHardware {
            width += Layout.fanItemWidth
            itemCount += 1
        }
        if settings.showBattery && hasBatteryHardware {
            width += Layout.batteryItemWidth
            itemCount += 1
        }

        let gap = settings.showStatusBarSeparator
            ? CGFloat(settings.statusBarSeparatorWidth)
            : Layout.defaultSeparatorWidth
        if itemCount > 1 {
            width += CGFloat(itemCount - 1) * gap
        }

        return max(width, 20)
    }

    // MARK: - Drawing

    /// Width of the rendered image, derived from the items (not the view frame) so it is
    /// independent of layout/autoresize timing.
    private var renderWidth: CGFloat {
        guard !displayItems.isEmpty else { return 20 }
        let items = displayItems.reduce(0) { $0 + $1.width }
        let separators = CGFloat(displayItems.count - 1) * separatorWidth
        return max(items + separators, 20)
    }

    private var usesColoredNetwork: Bool {
        networkColorStyle == .traffic
    }

    /// Renders the current items into a template image and hands it to the button. AppKit
    /// then tints it to the menu-bar foreground colour (white on a dark bar, black on a light
    /// one), so text adapts identically to the logo/fan template icons.
    ///
    /// Traffic-coloured network breaks the template contract (tint would wash out blue/green),
    /// so that mode draws with appearance-resolved colours instead.
    private func renderAndApply() {
        hostButton?.image = renderImage()
    }

    private func renderImage() -> NSImage {
        let size = NSSize(width: renderWidth, height: Layout.itemHeight)
        let colored = usesColoredNetwork
        let image = NSImage(size: size, flipped: false) { [weak self] rect in
            self?.drawContents(in: rect, colored: colored)
            return true
        }
        image.isTemplate = !colored
        return image
    }

    private func drawContents(in bounds: NSRect, colored: Bool) {
        // Template mode: opaque black; tinting keys off alpha only.
        // Coloured mode: resolve against the menu-bar appearance so non-network items stay legible.
        let textColor: NSColor
        if colored {
            textColor = resolvedMenuBarForeground()
        } else {
            textColor = NSColor.black
        }
        var xOffset: CGFloat = 0

        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)

            if item.isLogo {
                drawLogo(in: itemRect, tintColor: textColor)
            } else if item.isFan {
                // Transparent slot; `fanLayer` draws the spinning icon.
            } else if item.isNetwork {
                drawNetwork(item, in: itemRect, textColor: textColor, colored: colored)
            } else {
                drawStat(item, in: itemRect, textColor: textColor)
            }

            xOffset += item.width

            if index < displayItems.count - 1 {
                if drawsSeparator {
                    drawSeparator(at: xOffset, height: bounds.height, colored: colored)
                }
                xOffset += separatorWidth
            }
        }
    }

    private func drawSeparator(at xOffset: CGFloat, height: CGFloat, colored: Bool) {
        let lineWidth = min(Layout.separatorLineWidth, separatorWidth)
        let x = xOffset + (separatorWidth - lineWidth) / 2
        let inset: CGFloat = 4
        let rect = NSRect(x: x, y: inset, width: lineWidth, height: max(height - inset * 2, 1))
        let color: NSColor
        if colored {
            color = resolvedMenuBarForeground().withAlphaComponent(0.35)
        } else {
            color = NSColor.black.withAlphaComponent(0.35)
        }
        color.setFill()
        rect.fill()
    }

    private func resolvedMenuBarForeground() -> NSColor {
        let appearance = hostButton?.effectiveAppearance ?? effectiveAppearance
        var color = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            let tint = hostButton?.contentTintColor ?? NSColor.labelColor
            color = tint.usingColorSpace(.deviceRGB) ?? tint
        }
        return color
    }

    /// Draws the app logo from Assets. Template mode leaves tinting to AppKit;
    /// coloured mode paints the silhouette with the resolved menu-bar foreground.
    private func drawLogo(in itemRect: NSRect, tintColor: NSColor) {
        guard let image = NSImage(named: "StatusIcon") else { return }
        let iconSize: CGFloat = 16
        let iconRect = NSRect(
            x: itemRect.midX - iconSize / 2,
            y: itemRect.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        if usesColoredNetwork {
            image.isTemplate = false
            let tinted = NSImage(size: iconRect.size, flipped: false) { rect in
                image.draw(in: rect)
                tintColor.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: iconRect)
        } else {
            image.isTemplate = true
            image.draw(in: iconRect)
        }
    }

    /// 网络项特殊绘制：箭头固定，数值等宽；单位（KB/s…）弱化为细体 + 淡灰，与其他项一致。
    private func drawNetwork(
        _ item: DisplayItem,
        in itemRect: NSRect,
        textColor: NSColor,
        colored: Bool
    ) {
        let upColor: NSColor
        let downColor: NSColor
        if colored {
            upColor = NSColor.systemBlue
            downColor = NSColor.systemGreen
        } else {
            upColor = textColor
            downColor = textColor
        }
        let upArrowAttrs: [NSAttributedString.Key: Any] = [
            .font: Layout.networkFont,
            .foregroundColor: upColor
        ]
        let downArrowAttrs: [NSAttributedString.Key: Any] = [
            .font: Layout.networkFont,
            .foregroundColor: downColor
        ]
        let arrowXOffset: CGFloat = 2
        let globalYOffset: CGFloat = -1
        let valueX = itemRect.origin.x + arrowXOffset + Layout.arrowWidth

        let upY = itemRect.midY + globalYOffset
        "↑".draw(at: NSPoint(x: itemRect.origin.x + arrowXOffset, y: upY), withAttributes: upArrowAttrs)
        networkValue(item.value, textColor: upColor).draw(at: NSPoint(x: valueX, y: upY))

        let textHeight = item.label.size(withAttributes: downArrowAttrs).height
        let downY = itemRect.midY - textHeight + 1 + globalYOffset
        "↓".draw(at: NSPoint(x: itemRect.origin.x + arrowXOffset, y: downY), withAttributes: downArrowAttrs)
        networkValue(item.label, textColor: downColor).draw(at: NSPoint(x: valueX, y: downY))
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
                xOffset += separatorWidth
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

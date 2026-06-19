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
        static let fanIconSize: CGFloat = 14
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

    /// Fan-spin animation tuning, mirrored from `SpinningFanIcon` in OverviewTabView.
    private enum Fan {
        static let maxRevPerSecond: Double = 3.0   // 视觉封顶：最快每秒 3 圈
        static let rpmAtMaxSpeed: Double = 5000    // 达到该转速即封顶
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

    private var fanRPM: Int?
    private var fanAngle: CGFloat = 0
    private var fanLink: CADisplayLink?
    private var lastFanTimestamp: CFTimeInterval = 0

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        fanLink?.invalidate()
    }

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

        // Fan（图标按转速旋转，无数字/标签 → 固定宽度，不抖动）
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
        updateFanAnimation()

        // Battery（充电/已充满前缀闪电；无电池显示横杠）
        if settings.showBattery {
            let batteryText: String
            switch battery.state {
            case .noBattery:
                batteryText = "—"
            case .charging, .charged:
                batteryText = "⚡\(Int(battery.percent.rounded()))%"
            case .discharging:
                batteryText = "\(Int(battery.percent.rounded()))%"
            }
            displayItems.append(DisplayItem(
                value: batteryText,
                label: "BAT",
                width: Layout.batteryItemWidth,
                isLogo: false
            ))
        }

        needsDisplay = true
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let textColor = NSColor.labelColor
        var xOffset: CGFloat = 0

        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)

            if item.isLogo {
                drawLogo(in: itemRect)
            } else if item.isFan {
                drawFan(in: itemRect)
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

    /// Draws the fan as a `fanblades.fill` glyph rotated to the current animation angle.
    /// Spin speed tracks RPM (see `Fan`); RPM 0 / unknown → static glyph.
    private func drawFan(in itemRect: NSRect) {
        guard let image = NSImage(systemSymbolName: "fanblades.fill", accessibilityDescription: "Fan") else { return }
        image.isTemplate = true
        let size = Layout.fanIconSize
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: itemRect.midX, yBy: itemRect.midY)
        transform.rotate(byDegrees: -fanAngle) // 负角度 → 顺时针
        transform.concat()
        image.draw(in: NSRect(x: -size / 2, y: -size / 2, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
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

    // MARK: - Fan animation

    /// Starts/pauses the per-frame spin link: run only when the fan is shown and RPM > 0.
    private func updateFanAnimation() {
        guard (fanRPM ?? 0) > 0 else {
            fanLink?.isPaused = true
            return
        }
        ensureFanLink().isPaused = false
    }

    private func ensureFanLink() -> CADisplayLink {
        if let fanLink { return fanLink }
        let link = displayLink(target: self, selector: #selector(stepFan(_:)))
        link.add(to: .main, forMode: .common)
        lastFanTimestamp = 0
        fanLink = link
        return link
    }

    /// Accumulates rotation each frame, skipping abnormal gaps (display sleep/resume) to avoid jumps.
    @objc private func stepFan(_ link: CADisplayLink) {
        let now = link.timestamp
        defer { lastFanTimestamp = now }
        guard lastFanTimestamp > 0 else { return }
        let dt = now - lastFanTimestamp
        guard dt > 0, dt < 1 else { return }
        fanAngle = (fanAngle + Self.fanDegreesPerSecond(fanRPM) * dt).truncatingRemainder(dividingBy: 360)
        needsDisplay = true
    }

    /// 当前角速度（度/秒）：RPM 线性映射并封顶。
    private static func fanDegreesPerSecond(_ rpm: Int?) -> CGFloat {
        guard let rpm, rpm > 0 else { return 0 }
        let revPerSec = min(Double(rpm) / Fan.rpmAtMaxSpeed, 1.0) * Fan.maxRevPerSecond
        return CGFloat(revPerSec * 360.0)
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

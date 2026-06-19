//
//  StatusBarView.swift
//  Light Stats
//
//  Created on 2024/12/24.
//

import AppKit

final class StatusBarView: NSView {

    // MARK: - Constants

    private enum Layout {
        static let logoWidth: CGFloat = 16
        static let percentItemWidth: CGFloat = 26  // CPU, GPU, MEM (e.g., "99%")
        static let diskItemWidth: CGFloat = 46     // DISK (e.g., "999 GB")
        static let networkItemWidth: CGFloat = 56  // NET (e.g., "↑0.0 KB/s" / "↓0.0 KB/s")
        // FAN: 4-digit "9999 RPM" ≈ 56.9pt @ valueFont; +~2.5pt padding/side (matches DISK).
        static let fanItemWidth: CGFloat = 62
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
    }

    // MARK: - Data

    private var displayItems: [DisplayItem] = []

    private struct DisplayItem {
        let value: String
        let label: String
        let width: CGFloat
        let isLogo: Bool
        let isNetwork: Bool

        init(value: String, label: String = "", width: CGFloat, isLogo: Bool, isNetwork: Bool = false) {
            self.value = value
            self.label = label
            self.width = width
            self.isLogo = isLogo
            self.isNetwork = isNetwork
        }
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
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

        // Fan
        if settings.showFan {
            let fanText = fan.map { "\($0) RPM" } ?? "—"
            displayItems.append(DisplayItem(
                value: fanText,
                label: "FAN",
                width: Layout.fanItemWidth,
                isLogo: false
            ))
        }

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

        // Get appearance-aware colors
        let textColor = NSColor.labelColor
        _ = NSColor.secondaryLabelColor

        var xOffset: CGFloat = 0

        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)

            if item.isLogo {
                // Draw logo icon from Assets
                if let image = NSImage(named: "StatusIcon") {
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
            } else if item.isNetwork {
                // 网络项特殊绘制：箭头固定，数值等宽
                let netAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.networkFont,
                    .foregroundColor: textColor
                ]
                let lineSpacing: CGFloat = 0
                let arrowXOffset: CGFloat = 2
                let globalYOffset: CGFloat = -1 // 整体下移 1 单位

                // 绘制上传 (上行)
                let upArrow = "↑"
                let upValue = item.value

                let upArrowPoint = NSPoint(x: itemRect.origin.x + arrowXOffset, y: itemRect.midY + lineSpacing + globalYOffset)
                upArrow.draw(at: upArrowPoint, withAttributes: netAttrs)

                let upValuePoint = NSPoint(
                    x: itemRect.origin.x + arrowXOffset + Layout.arrowWidth,
                    y: itemRect.midY + lineSpacing + globalYOffset
                )
                upValue.draw(at: upValuePoint, withAttributes: netAttrs)

                // 绘制下载 (下行)
                let downArrow = "↓"
                let downValue = item.label

                let textHeight = item.label.size(withAttributes: netAttrs).height
                let downY = itemRect.midY - textHeight + 1 + globalYOffset

                let downArrowPoint = NSPoint(x: itemRect.origin.x + arrowXOffset, y: downY)
                downArrow.draw(at: downArrowPoint, withAttributes: netAttrs)

                let downValuePoint = NSPoint(x: itemRect.origin.x + arrowXOffset + Layout.arrowWidth, y: downY)
                downValue.draw(at: downValuePoint, withAttributes: netAttrs)
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
                attributes: [.font: Layout.unitFont, .foregroundColor: textColor.withAlphaComponent(0.7)]
            ))
        }
        let valueSize = value.size()
        value.draw(at: NSPoint(x: itemRect.midX - valueSize.width / 2, y: itemRect.height / 2 - 2))

        // Label (bottom) - clearer font, tighter spacing
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: Layout.labelFont,
            .foregroundColor: textColor.withAlphaComponent(0.7)
        ]
        let labelSize = item.label.size(withAttributes: labelAttrs)
        let labelPoint = NSPoint(
            x: itemRect.midX - labelSize.width / 2,
            y: itemRect.height / 2 - labelSize.height - 2
        )
        item.label.draw(at: labelPoint, withAttributes: labelAttrs)
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

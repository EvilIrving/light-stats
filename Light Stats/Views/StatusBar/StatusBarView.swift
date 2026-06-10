import AppKit

final class StatusBarView: NSView {

    // MARK: - Constants

    private enum Layout {
        static let logoWidth: CGFloat = 16
        static let percentItemWidth: CGFloat = 26
        static let diskItemWidth: CGFloat = 46
        static let networkItemWidth: CGFloat = 56
        static let fanItemWidth: CGFloat = 50
        static let batteryItemWidth: CGFloat = 34
        static let healthItemWidth: CGFloat = 30
        static let separatorWidth: CGFloat = 2
        static let itemHeight: CGFloat = 22
        static let arrowWidth: CGFloat = 8

        // Compact micro constants
        static let microItemWidth: CGFloat = 28
        static let microNetworkWidth: CGFloat = 56
        static let microSeparator: CGFloat = 2

        // Terminal inline constants
        static let terminalFontSize: CGFloat = 10

        static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        static let labelFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        static let logoFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        static let networkFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        static let microFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        static let microLabelFont = NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .medium)
        static let terminalFont = NSFont.monospacedDigitSystemFont(ofSize: terminalFontSize, weight: .medium)
    }

    // MARK: - State

    private var displayItems: [DisplayItem] = []
    private var currentStatusBarStyle: StatusBarStyle = .stackedLabelValue
    private var currentTheme: AppTheme = .classic

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Public

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
        let preset = settings.appearancePreset
        currentStatusBarStyle = preset.layout.statusBarStyle
        currentTheme = preset.theme
        displayItems.removeAll()

        switch currentStatusBarStyle {
        case .stackedLabelValue:
            buildClassicItems(cpu: cpu, gpu: gpu, memory: memory, disk: disk, upload: upload, download: download, fan: fan, battery: battery, health: health, settings: settings)
        case .compactMicro:
            buildCompactMicroItems(cpu: cpu, gpu: gpu, memory: memory, disk: disk, upload: upload, download: download, fan: fan, battery: battery, health: health, settings: settings)
        case .terminalInline:
            buildTerminalItems(cpu: cpu, gpu: gpu, memory: memory, disk: disk, upload: upload, download: download, fan: fan, battery: battery, health: health, settings: settings)
        }

        needsDisplay = true
    }

    static func calculateWidth(settings: any SettingsManaging) -> CGFloat {
        let preset = settings.appearancePreset
        switch preset.layout.statusBarStyle {
        case .stackedLabelValue:
            return classicWidth(settings: settings)
        case .compactMicro:
            return compactMicroWidth(settings: settings)
        case .terminalInline:
            return terminalInlineWidth(settings: settings)
        }
    }

    // MARK: - Width Calculation

    private static func classicWidth(settings: any SettingsManaging) -> CGFloat {
        var width: CGFloat = 0; var itemCount = 0
        if settings.showLogo { width += Layout.logoWidth; itemCount += 1 }
        if settings.showCPU { width += Layout.percentItemWidth; itemCount += 1 }
        if settings.showGPU { width += Layout.percentItemWidth; itemCount += 1 }
        if settings.showMemory { width += Layout.percentItemWidth; itemCount += 1 }
        if settings.showDisk { width += Layout.diskItemWidth; itemCount += 1 }
        if settings.showNetwork { width += Layout.networkItemWidth; itemCount += 1 }
        if settings.showFan { width += Layout.fanItemWidth; itemCount += 1 }
        if settings.showBattery { width += Layout.batteryItemWidth; itemCount += 1 }
        if settings.showHealth { width += Layout.healthItemWidth; itemCount += 1 }
        if itemCount > 1 { width += CGFloat(itemCount - 1) * Layout.separatorWidth }
        return max(width, 20)
    }

    private static func compactMicroWidth(settings: any SettingsManaging) -> CGFloat {
        var width: CGFloat = 0; var itemCount = 0
        if settings.showLogo { width += Layout.logoWidth; itemCount += 1 }
        if settings.showCPU { width += Layout.microItemWidth; itemCount += 1 }
        if settings.showGPU { width += Layout.microItemWidth; itemCount += 1 }
        if settings.showMemory { width += Layout.microItemWidth; itemCount += 1 }
        if settings.showNetwork { width += Layout.microNetworkWidth; itemCount += 1 }
        if settings.showBattery { width += Layout.microItemWidth; itemCount += 1 }
        if settings.showHealth { width += Layout.microItemWidth; itemCount += 1 }
        if itemCount > 1 { width += CGFloat(itemCount - 1) * Layout.microSeparator }
        return max(width, 20)
    }

    private static func terminalInlineWidth(settings: any SettingsManaging) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: Layout.terminalFontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var text = ""
        if settings.showCPU { text += "cpu:99% " }
        if settings.showGPU { text += "gpu:99% " }
        if settings.showMemory { text += "mem:99% " }
        if settings.showNetwork { text += "net:↓99K↑99K " }
        if settings.showBattery { text += "bat:99% " }
        let size = (text as NSString).size(withAttributes: attrs)
        return max(size.width + 4, 20)
    }

    // MARK: - Item Builders

    private func buildClassicItems(cpu: Double, gpu: Double?, memory: Double, disk: UInt64, upload: Double, download: Double, fan: Int?, battery: BatteryInfo, health: HealthScore, settings: any SettingsManaging) {
        if settings.showLogo {
            displayItems.append(DisplayItem(value: "◉", label: "", width: Layout.logoWidth, isLogo: true))
        }
        if settings.showCPU {
            displayItems.append(DisplayItem(value: String(format: "%.0f%%", cpu), label: "CPU", width: Layout.percentItemWidth, isLogo: false))
        }
        if settings.showGPU {
            let t = gpu.map { String(format: "%.0f%%", $0) } ?? "N/A"
            displayItems.append(DisplayItem(value: t, label: "GPU", width: Layout.percentItemWidth, isLogo: false))
        }
        if settings.showMemory {
            displayItems.append(DisplayItem(value: String(format: "%.0f%%", memory), label: "MEM", width: Layout.percentItemWidth, isLogo: false))
        }
        if settings.showDisk {
            displayItems.append(DisplayItem(value: ByteFormatter.formatDisk(disk), label: "DISK", width: Layout.diskItemWidth, isLogo: false))
        }
        if settings.showNetwork {
            displayItems.append(DisplayItem(value: ByteFormatter.formatSpeed(upload), label: ByteFormatter.formatSpeed(download), width: Layout.networkItemWidth, isLogo: false, isNetwork: true))
        }
        if settings.showFan {
            let t = fan.map { "\($0) RPM" } ?? "-- RPM"
            displayItems.append(DisplayItem(value: t, label: "FAN", width: Layout.fanItemWidth, isLogo: false))
        }
        if settings.showBattery {
            let t: String
            switch battery.state {
            case .noBattery: t = "N/A"
            case .charging, .charged: t = "⚡\(Int(battery.percent.rounded()))%"
            case .discharging: t = "\(Int(battery.percent.rounded()))%"
            }
            displayItems.append(DisplayItem(value: t, label: "BAT", width: Layout.batteryItemWidth, isLogo: false))
        }
        if settings.showHealth {
            displayItems.append(DisplayItem(value: "\(health.score)", label: "HLT", width: Layout.healthItemWidth, isLogo: false))
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func buildCompactMicroItems(cpu: Double, gpu: Double?, memory: Double, disk _: UInt64, upload: Double, download: Double, fan _: Int?, battery: BatteryInfo, health: HealthScore, settings: any SettingsManaging) {
        if settings.showLogo {
            displayItems.append(DisplayItem(value: "◉", label: "", width: Layout.logoWidth, isLogo: true))
        }
        if settings.showCPU {
            displayItems.append(DisplayItem(value: "C\(Int(cpu.rounded()))", label: "", width: Layout.microItemWidth, isLogo: false))
        }
        if settings.showGPU {
            let t = gpu.map { "G\(Int($0.rounded()))" } ?? "G--"
            displayItems.append(DisplayItem(value: t, label: "", width: Layout.microItemWidth, isLogo: false))
        }
        if settings.showMemory {
            displayItems.append(DisplayItem(value: "M\(Int(memory.rounded()))", label: "", width: Layout.microItemWidth, isLogo: false))
        }
        if settings.showNetwork {
            let down = compactSpeed(download); let up = compactSpeed(upload)
            displayItems.append(DisplayItem(value: "↓\(down)", label: "↑\(up)", width: Layout.microNetworkWidth, isLogo: false, isNetwork: true))
        }
        if settings.showBattery {
            let t: String
            if battery.state == .charging || battery.state == .charged {
                t = "⚡\(Int(battery.percent.rounded()))"
            } else if battery.state == .noBattery {
                t = "--"
            } else {
                t = "\(Int(battery.percent.rounded()))"
            }
            displayItems.append(DisplayItem(value: t, label: "", width: Layout.microItemWidth, isLogo: false))
        }
        if settings.showHealth {
            displayItems.append(DisplayItem(value: "H\(health.score)", label: "", width: Layout.microItemWidth, isLogo: false))
        }
    }

    private func compactSpeed(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 { return String(format: "%.1fM", bytesPerSecond / 1_000_000) }
        if bytesPerSecond >= 1_000 { return String(format: "%.0fK", bytesPerSecond / 1_000) }
        return "\(Int(bytesPerSecond))"
    }

    private func buildTerminalItems(cpu: Double, gpu: Double?, memory: Double, disk _: UInt64, upload: Double, download: Double, fan _: Int?, battery: BatteryInfo, health: HealthScore, settings: any SettingsManaging) {
        // Terminal style puts everything in one display item rendered as a single line
        var parts: [String] = []
        if settings.showCPU { parts.append("cpu:\(Int(cpu.rounded()))%") }
        if settings.showGPU {
            let g = gpu.map { "\(Int($0.rounded()))%" } ?? "N/A"
            parts.append("gpu:\(g)")
        }
        if settings.showMemory { parts.append("mem:\(Int(memory.rounded()))%") }
        if settings.showNetwork {
            parts.append("net:↓\(compactSpeed(download))↑\(compactSpeed(upload))")
        }
        if settings.showBattery {
            switch battery.state {
            case .noBattery: parts.append("bat:--")
            case .charging, .charged: parts.append("bat:⚡\(Int(battery.percent.rounded()))%")
            case .discharging: parts.append("bat:\(Int(battery.percent.rounded()))%")
            }
        }
        if settings.showHealth { parts.append("hlt:\(health.score)") }
        let value = parts.joined(separator: " ")
        displayItems.append(DisplayItem(value: value, label: "", width: bounds.width, isLogo: false))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switch currentStatusBarStyle {
        case .stackedLabelValue: drawClassic()
        case .compactMicro: drawCompactMicro()
        case .terminalInline: drawTerminal()
        }
    }

    // MARK: Classic drawing

    private func drawClassic() {
        let textColor = currentTheme.statusBarTextColor

        var xOffset: CGFloat = 0
        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)

            if item.isLogo {
                if let image = NSImage(named: "StatusIcon") {
                    image.isTemplate = true
                    let iconSize: CGFloat = 16
                    let iconRect = NSRect(x: itemRect.midX - iconSize / 2, y: itemRect.midY - iconSize / 2, width: iconSize, height: iconSize)
                    image.draw(in: iconRect)
                }
            } else if item.isNetwork {
                let netAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.networkFont,
                    .foregroundColor: textColor
                ]
                let lineSpacing: CGFloat = 0
                let arrowXOffset: CGFloat = 2
                let globalYOffset: CGFloat = -1
                let upArrow = "↑"
                let upValue = item.value
                let upArrowPoint = NSPoint(x: itemRect.origin.x + arrowXOffset, y: itemRect.midY + lineSpacing + globalYOffset)
                upArrow.draw(at: upArrowPoint, withAttributes: netAttrs)
                let upValuePoint = NSPoint(x: itemRect.origin.x + arrowXOffset + Layout.arrowWidth, y: itemRect.midY + lineSpacing + globalYOffset)
                upValue.draw(at: upValuePoint, withAttributes: netAttrs)
                let downArrow = "↓"
                let downValue = item.label
                let textHeight = item.label.size(withAttributes: netAttrs).height
                let downY = itemRect.midY - textHeight + 1 + globalYOffset
                let downArrowPoint = NSPoint(x: itemRect.origin.x + arrowXOffset, y: downY)
                downArrow.draw(at: downArrowPoint, withAttributes: netAttrs)
                let downValuePoint = NSPoint(x: itemRect.origin.x + arrowXOffset + Layout.arrowWidth, y: downY)
                downValue.draw(at: downValuePoint, withAttributes: netAttrs)
            } else {
                let valueAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.valueFont,
                    .foregroundColor: textColor
                ]
                let valueSize = item.value.size(withAttributes: valueAttrs)
                let valuePoint = NSPoint(x: itemRect.midX - valueSize.width / 2, y: itemRect.height / 2 - 2)
                item.value.draw(at: valuePoint, withAttributes: valueAttrs)

                let labelAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.labelFont,
                    .foregroundColor: textColor.withAlphaComponent(0.7)
                ]
                let labelSize = item.label.size(withAttributes: labelAttrs)
                let labelPoint = NSPoint(x: itemRect.midX - labelSize.width / 2, y: itemRect.height / 2 - labelSize.height - 2)
                item.label.draw(at: labelPoint, withAttributes: labelAttrs)
            }

            xOffset += item.width
            if index < displayItems.count - 1 { xOffset += Layout.separatorWidth }
        }
    }

    // MARK: Compact Micro drawing

    private func drawCompactMicro() {
        let textColor = currentTheme.statusBarTextColor

        var xOffset: CGFloat = 0
        for (index, item) in displayItems.enumerated() {
            let itemRect = NSRect(x: xOffset, y: 0, width: item.width, height: bounds.height)

            if item.isLogo {
                if let image = NSImage(named: "StatusIcon") {
                    image.isTemplate = true
                    let iconSize: CGFloat = 14
                    let iconRect = NSRect(x: itemRect.midX - iconSize / 2, y: itemRect.midY - iconSize / 2, width: iconSize, height: iconSize)
                    image.draw(in: iconRect)
                }
            } else if item.isNetwork {
                // Two-line: ↓down on top, ↑up on bottom
                let netAttrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.microLabelFont,
                    .foregroundColor: textColor
                ]
                let topStr = item.value   // "↓1.2M"
                let bottomStr = item.label // "↑320K"

                let topSize = topStr.size(withAttributes: netAttrs)
                let bottomSize = bottomStr.size(withAttributes: netAttrs)

                let topPoint = NSPoint(x: itemRect.midX - topSize.width / 2, y: itemRect.midY + 1.5)
                topStr.draw(at: topPoint, withAttributes: netAttrs)

                let bottomPoint = NSPoint(x: itemRect.midX - bottomSize.width / 2, y: itemRect.midY - bottomSize.height - 1.5)
                bottomStr.draw(at: bottomPoint, withAttributes: netAttrs)
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: Layout.microFont,
                    .foregroundColor: textColor
                ]
                let size = item.value.size(withAttributes: attrs)
                let point = NSPoint(x: itemRect.midX - size.width / 2, y: itemRect.midY - size.height / 2)
                item.value.draw(at: point, withAttributes: attrs)
            }

            xOffset += item.width
            if index < displayItems.count - 1 { xOffset += Layout.microSeparator }
        }
    }

    // MARK: Terminal drawing

    private func drawTerminal() {
        let textColor = currentTheme.statusBarTextColor
        guard let item = displayItems.first else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Layout.terminalFont,
            .foregroundColor: textColor
        ]
        let size = item.value.size(withAttributes: attrs)
        let point = NSPoint(x: 2, y: (bounds.height - size.height) / 2)
        item.value.draw(at: point, withAttributes: attrs)
    }
}

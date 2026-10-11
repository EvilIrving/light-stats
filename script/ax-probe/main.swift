//
//  ax-probe — 窗口管理的真机探针（手动验收工具，不进 CI）
//
// 存在的理由：验窗口管理只能对真实 App 操作，而"读帧 / 拖拽 / 滚动 / 查命中 / 看 subrole"
//  这些原语每次现写一遍 Swift 是浪费，而且每次都会写出不同的细节（按 CFEqual 判窗口身份、
//  CFTypeRef 变量复用导致编译不过、忘了读回验证）。这里只写一次，验收脚本与排查都调它。
//
//  用法：./script/ax-probe.sh <command> [args]
//  全部命令见 ./script/ax-probe.sh help
//
//  坐标一律是 Accessibility（左上原点，y 向下），与 App 内部一致。
//

import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Accessibility 读取

func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable: DarwinBoolean = false
    guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else { return false }
    return settable.boolValue
}

func frame(of element: AXUIElement) -> CGRect? {
    var position = CGPoint.zero
    var size = CGSize.zero
    var positionValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          let positionValue, CFGetTypeID(positionValue) == AXValueGetTypeID(),
          AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position) else { return nil }
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let sizeValue, CFGetTypeID(sizeValue) == AXValueGetTypeID(),
          AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
    return CGRect(origin: position, size: size)
}

func describes(_ rect: CGRect?) -> String {
    guard let rect else { return "none" }
    return "\(Int(rect.minX.rounded())) \(Int(rect.minY.rounded())) \(Int(rect.width.rounded())) \(Int(rect.height.rounded()))"
}

func describesCompact(_ rect: CGRect?) -> String {
    guard let rect else { return "none" }
    return "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())) \(Int(rect.width.rounded()))x\(Int(rect.height.rounded()))"
}

func applicationElement(_ pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    return app
}

func axWindows(_ pid: pid_t) -> [AXUIElement] {
    attribute(applicationElement(pid), kAXWindowsAttribute as String) ?? []
}

/// 按标题找窗口。给了空串就用第一个。找不到返回 nil。
func window(_ pid: pid_t, title: String?) -> AXUIElement? {
    let windows = axWindows(pid)
    guard let title, !title.isEmpty else { return windows.first }
    let matches = windows.filter { ((attribute($0, kAXTitleAttribute as String) ?? "") as String) == title }
    return matches.count == 1 ? matches.first : nil
}

let controlRoles: Set<String> = [
    "AXButton", "AXTextField", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
    "AXTabGroup", "AXScrollBar", "AXMenuButton", "AXSlider", "AXLink", "AXComboBox",
    "AXDisclosureTriangle", "AXSegmentedControl", "AXIncrementor"
]

let trafficLightSubroles: Set<String> = [
    "AXCloseButton", "AXMinimizeButton", "AXFullScreenButton", "AXZoomButton"
]

/// 红绿灯簇：系统给这个窗口画了标题栏的证据。分类判据用它，而不是 App 自报的 subrole。
func trafficLights(of element: AXUIElement) -> CGRect? {
    var union: CGRect?
    for child in (attribute(element, kAXChildrenAttribute as String) ?? []) as [AXUIElement] {
        let subrole: String = attribute(child, kAXSubroleAttribute as String) ?? ""
        guard trafficLightSubroles.contains(subrole), let childFrame = frame(of: child) else { continue }
        union = union.map { $0.union(childFrame) } ?? childFrame
    }
    return union
}

func isMainOrFocused(_ pid: pid_t, _ element: AXUIElement) -> (main: Bool, focused: Bool) {
    let app = applicationElement(pid)
    let main: AXUIElement? = attribute(app, kAXMainWindowAttribute as String)
    let focused: AXUIElement? = attribute(app, kAXFocusedWindowAttribute as String)
    return (main.map { CFEqual($0, element) } ?? false, focused.map { CFEqual($0, element) } ?? false)
}

// MARK: - WindowServer（不需要任何权限，用来拿 on screen 与 layer）

struct WindowServerEntry {
    var windowID: CGWindowID
    var pid: pid_t
    var layer: Int
    var onScreen: Bool
    var bounds: CGRect
}

func windowServerEntries(all: Bool = true) -> [WindowServerEntry] {
    let options: CGWindowListOption = all ? [.optionAll, .excludeDesktopElements] : [.optionOnScreenOnly, .excludeDesktopElements]
    guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
    return raw.compactMap { info in
        guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let layer = info[kCGWindowLayer as String] as? Int,
              let windowID = info[kCGWindowNumber as String] as? CGWindowID,
              let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        return WindowServerEntry(
            windowID: windowID,
            pid: pid,
            layer: layer,
            onScreen: (info[kCGWindowIsOnscreen as String] as? Bool) ?? false,
            bounds: CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        )
    }
}

/// 与 AX 窗口对应的 WindowServer 记录：同 pid 且 frame 几乎相同的那条。
/// 按 frame 认，不按 CFEqual——命中测试返回的窗口元素与 AXWindows 里的不是同一个引用。
func windowServerEntry(for element: AXUIElement, pid: pid_t) -> WindowServerEntry? {
    guard let target = frame(of: element) else { return nil }
    return windowServerEntries().first {
        $0.pid == pid && abs($0.bounds.minX - target.minX) <= 2 && abs($0.bounds.minY - target.minY) <= 2
            && abs($0.bounds.width - target.width) <= 2 && abs($0.bounds.height - target.height) <= 2
    }
}

// MARK: - 写入

func setPosition(_ element: AXUIElement, _ position: CGPoint) {
    var mutable = position
    guard let value = AXValueCreate(.cgPoint, &mutable) else { return }
    _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
}

func setSize(_ element: AXUIElement, _ size: CGSize) {
    var mutable = size
    guard let value = AXValueCreate(.cgSize, &mutable) else { return }
    _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
}

func close(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat) -> Bool {
    abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
        && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
}

/// Test setup and restoration only. Product behaviour is verified through drag events.
@discardableResult
func writeVerified(_ element: AXUIElement, _ target: CGRect) -> CGRect? {
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return nil }
    let enhanced = enhancedUserInterface(pid)
    if enhanced { setEnhancedUserInterface(pid, false) }
    defer { if enhanced { setEnhancedUserInterface(pid, true) } }
    var achieved: CGRect?
    var previous: CGRect?
    for _ in 0..<6 {
        setSize(element, target.size)
        setPosition(element, target.origin)
        setSize(element, target.size)
        usleep(90_000)
        achieved = frame(of: element)
        guard let achieved else { continue }
        if close(achieved, target, tolerance: 2) { return achieved }
        if let previous, close(previous, achieved, tolerance: 1) { return achieved }
        previous = achieved
    }
    return achieved
}

/// 修复前的写法：四连写、不等待、不复核。用来复现"App 忽略尺寸写入"那类故障。
func writeBurst(_ element: AXUIElement, _ target: CGRect) {
    setSize(element, target.size)
    setPosition(element, target.origin)
    setSize(element, target.size)
    setPosition(element, target.origin)
}

/// `AXEnhancedUserInterface`：开着的时候 App 会收下尺寸写入却保持原尺寸。
func enhancedUserInterface(_ pid: pid_t) -> Bool {
    (attribute(applicationElement(pid), "AXEnhancedUserInterface") as Bool?) ?? false
}

func setEnhancedUserInterface(_ pid: pid_t, _ enabled: Bool) {
    _ = AXUIElementSetAttributeValue(
        applicationElement(pid),
        "AXEnhancedUserInterface" as CFString,
        enabled ? kCFBooleanTrue : kCFBooleanFalse
    )
}

// MARK: - 合成输入

func post(_ type: CGEventType, _ point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func drag(from start: CGPoint, to end: CGPoint, steps: Int, stepMicros: UInt32, holdMicros: UInt32, preclick: Bool) {
    post(.mouseMoved, start)
    usleep(180_000)
    if preclick {
        post(.leftMouseDown, start)
        usleep(60_000)
        post(.leftMouseUp, start)
        usleep(350_000)
    }
    post(.leftMouseDown, start)
    usleep(120_000)
    for step in 1...max(steps, 1) {
        let progress = Double(step) / Double(max(steps, 1))
        post(.leftMouseDragged, CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        ))
        usleep(stepMicros)
    }
    if holdMicros > 0 { usleep(holdMicros) }
    post(.leftMouseUp, end)
}

/// 双指滚动：手指阶段 + 惯性尾巴，照触控板的时序。
func scroll(at point: CGPoint, dy: Int32, steps: Int, momentumSteps: Int) {
    func send(_ dy: Int32, phase: Int64, momentum: Int64) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                  wheel1: dy, wheel2: 0, wheel3: 0) else { return }
        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if phase != 0 { event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase) }
        if momentum != 0 { event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum) }
        event.post(tap: .cghidEventTap)
    }
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(150_000)
    send(0, phase: 1, momentum: 0)
    for _ in 0..<max(steps, 1) { send(dy, phase: 2, momentum: 0); usleep(9_000) }
    send(0, phase: 4, momentum: 0)
    for _ in 0..<max(momentumSteps, 0) { send(dy, phase: 0, momentum: 2); usleep(9_000) }
    send(0, phase: 0, momentum: 3)
}

// MARK: - 几何（期望值的独立算法）

/// 一块屏：整块与可见区，都换算到 Accessibility 空间。
func displayInAccessibility(at point: CGPoint) -> (whole: CGRect, visible: CGRect)? {
    guard let primary = NSScreen.screens.first else { return nil }
    let reference = primary.frame.maxY
    func flipped(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: reference - rect.maxY, width: rect.width, height: rect.height)
    }
    guard let screen = NSScreen.screens.first(where: { flipped($0.frame).contains(point) }) else { return nil }
    return (flipped(screen.frame), flipped(screen.visibleFrame))
}

func visibleAreaInAccessibility(at point: CGPoint) -> CGRect? {
    displayInAccessibility(at: point)?.visible
}

func wholeDisplayFrame(containing area: CGRect) -> CGRect? {
    displayInAccessibility(at: CGPoint(x: area.midX, y: area.midY))?.whole
}

/// 产品第一层的窗口角色白名单。这里独立写一份：验收要另一条实现说了算。
let allowedSubroles: Set<String> = ["AXStandardWindow", "AXDocumentWindow", "AXFloatingWindow"]

/// zone → 归一化矩形。这是产品边缘区域表里的目标集合，独立算一遍用来对答案。
func normalizedRect(for zone: String) -> (x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat)? {
    switch zone {
    case "leftHalf": return (0, 0, 0.5, 1)
    case "rightHalf": return (0.5, 0, 0.5, 1)
    case "topHalf": return (0, 0, 1, 0.5)
    case "bottomHalf": return (0, 0.5, 1, 0.5)
    case "topLeft": return (0, 0, 0.5, 0.5)
    case "topRight": return (0.5, 0, 0.5, 0.5)
    case "bottomLeft": return (0, 0.5, 0.5, 0.5)
    case "bottomRight": return (0.5, 0.5, 0.5, 0.5)
    case "leftThird": return (0, 0, 1.0 / 3, 1)
    case "leftTwoThirds": return (0, 0, 2.0 / 3, 1)
    case "centerThird": return (1.0 / 3, 0, 1.0 / 3, 1)
    case "rightTwoThirds": return (1.0 / 3, 0, 2.0 / 3, 1)
    case "rightThird": return (2.0 / 3, 0, 1.0 / 3, 1)
    case "maximize": return (0, 0, 1, 1)
    default: return nil
    }
}

/// zone → 一个落在该区域里的落点（边缘带按产品的阈值 24pt，角落约屏高的 4%，上限 48）。
func dropPoint(for zone: String, visible: CGRect, whole: CGRect) -> CGPoint? {
    let edge: CGFloat = 7
    let corner = min(max(visible.height * 0.04, 24), 48, whole.width * 0.18)
    let left = whole.minX + edge
    let right = whole.maxX - edge
    let top = visible.minY + edge
    let bottom = whole.maxY - edge
    let midY = visible.minY + visible.height / 2
    switch zone {
    case "leftHalf": return CGPoint(x: left, y: midY)
    case "rightHalf": return CGPoint(x: right, y: midY)
    case "topHalf": return CGPoint(x: left, y: visible.minY + (whole.maxY - visible.minY) * 0.09)
    case "bottomHalf": return CGPoint(x: left, y: visible.minY + (whole.maxY - visible.minY) * 0.91)
    case "topLeft": return CGPoint(x: left, y: top)
    case "topRight": return CGPoint(x: right, y: top)
    case "bottomLeft": return CGPoint(x: left, y: bottom)
    case "bottomRight": return CGPoint(x: right, y: bottom)
    case "leftThird": return CGPoint(x: whole.minX + whole.width * 0.1, y: bottom)
    case "leftTwoThirds": return CGPoint(x: whole.minX + whole.width * 0.3, y: bottom)
    case "centerThird": return CGPoint(x: whole.minX + whole.width * 0.5, y: bottom)
    case "rightTwoThirds": return CGPoint(x: whole.minX + whole.width * 0.7, y: bottom)
    case "rightThird": return CGPoint(x: whole.minX + whole.width * 0.9, y: bottom)
    case "maximize": return CGPoint(x: whole.minX + max(corner + edge, whole.width * 0.15), y: top)
    default: return nil
    }
}

/// 拖拽能到达的全部目标，供脚本遍历——这不是"写死一个用例"，是产品区域表本身。
let snapZones = [
    "leftHalf", "rightHalf", "topHalf", "bottomHalf",
    "topLeft", "topRight", "bottomLeft", "bottomRight",
    "leftThird", "leftTwoThirds", "centerThird", "rightTwoThirds", "rightThird",
    "maximize"
]

// MARK: - 命令

let arguments = CommandLine.arguments

func fail(_ message: String) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(2)
}

func requireTrust() {
    guard AXIsProcessTrusted() else {
        fail("辅助功能权限缺失：运行本工具需要被授权（系统设置 → 隐私与安全性 → 辅助功能）。")
    }
}

let help = """
ax-probe — 窗口管理真机探针。坐标一律 Accessibility（左上原点，y 向下）。

  apps                               发现有窗口的应用，输出 pid|显示名
  zones                              区域用例名称
  expected <zone> <x> <y>             独立计算该屏的目标矩形
  drop-point <zone> <x> <y>           区域内的鼠标释放点
  raise <pid> <标题>                  激活应用并提起指定窗口
  trust                              检查辅助功能权限
  list <pid> [--all]                 每个窗口：role|subrole|标题|frame|红绿灯|主|焦点|可移动|onscreen|layer
  frame <pid> [标题]                 读窗口 frame
  place <pid> <标题> x y w h         按引擎的写入契约摆好一个窗口（写→落定→复核重试）
  place <pid> <标题> x y w h --burst 用修复前的四连写（复现"App 忽略尺寸"）
  enhanced <pid> read|on|off         读写 AXEnhancedUserInterface
  hit <x> <y>                        命中测试，打印 AX 父链
  grab <pid> <标题>                  顶部一个不落在控件上的可拖点（已校验命中同一窗口）
  drag <fx> <fy> <tx> <ty> [步数] [每步µs] [松手前µs] [--preclick]
  scroll <x> <y> <dy> [步数] [惯性步数]
  poll <pid> [秒数] [Hz]             subrole/红绿灯/flap 的变化轨迹
  screen-left <x> <y>                该点所在显示器最左边的 x
  expected-left-half <x> <y>         该点所在显示器可见区左半边的 frame
"""

guard arguments.count > 1 else { print(help); exit(2) }

switch arguments[1] {
case "help", "--help", "-h":
    print(help)

case "trust":
    print(AXIsProcessTrusted() ? "trusted" : "untrusted")
    exit(AXIsProcessTrusted() ? 0 : 3)

case "apps":
    requireTrust()
    for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
        let eligible = axWindows(pid).contains { element in
            let role: String = attribute(element, kAXRoleAttribute as String) ?? ""
            let subrole: String = attribute(element, kAXSubroleAttribute as String) ?? ""
            return role == "AXWindow" && allowedSubroles.contains(subrole)
        }
        guard eligible else { continue }
        print("\(pid)|\(app.localizedName ?? "?")")
    }

case "list":
    requireTrust()
    guard let pid = pid_t(arguments[2]) else { fail("list <pid>") }
    let all = arguments.contains("--all")
    for element in axWindows(pid) {
        let role: String = attribute(element, kAXRoleAttribute as String) ?? "-"
        guard role == "AXWindow" else { continue }
        let subrole: String = attribute(element, kAXSubroleAttribute as String) ?? "-"
        let title: String = attribute(element, kAXTitleAttribute as String) ?? ""
        let lights = trafficLights(of: element) != nil
        let (isMain, isFocused) = isMainOrFocused(pid, element)
        let movable = isSettable(element, kAXPositionAttribute as String)
        let entry = windowServerEntry(for: element, pid: pid)
        guard all || entry?.onScreen != false || entry == nil else { continue }
        print([
            role, subrole, title.isEmpty ? "(无标题)" : title, describes(frame(of: element)),
            lights ? "红绿灯" : "-", isMain ? "主" : "-", isFocused ? "焦点" : "-",
            movable ? "可移动" : "不可移动",
            entry.map { $0.onScreen ? "onscreen" : "offscreen" } ?? "?",
            entry.map { "layer=\($0.layer)" } ?? "layer=?"
        ].joined(separator: "|"))
    }

case "raise":
    requireTrust()
    guard arguments.count > 3, let pid = pid_t(arguments[2]), let element = window(pid, title: arguments[3]) else {
        fail("raise <pid> <唯一的完整标题>")
    }
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    guard AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success else { exit(4) }
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
        fail("Target application did not become frontmost")
    }

case "frame":
    requireTrust()
    guard let pid = pid_t(arguments[2]), let element = window(pid, title: arguments.count > 3 ? arguments[3] : nil) else {
        print("none"); exit(4)
    }
    print(describes(frame(of: element)))

case "place":
    requireTrust()
    guard arguments.count >= 8, let pid = pid_t(arguments[2]), let element = window(pid, title: arguments[3]),
          let x = Double(arguments[4]), let y = Double(arguments[5]),
          let width = Double(arguments[6]), let height = Double(arguments[7]) else {
        fail("place <pid> <标题> x y w h [--burst]")
    }
    let target = CGRect(x: x, y: y, width: width, height: height)
    if arguments.contains("--burst") {
        writeBurst(element, target)
        usleep(700_000)
        print(describes(frame(of: element)))
    } else {
        print(describes(writeVerified(element, target)))
    }

case "enhanced":
    requireTrust()
    guard let pid = pid_t(arguments[2]), arguments.count > 3 else { fail("enhanced <pid> read|on|off") }
    switch arguments[3] {
    case "read": print(enhancedUserInterface(pid) ? "on" : "off")
    case "on": setEnhancedUserInterface(pid, true); print("on")
    case "off": setEnhancedUserInterface(pid, false); print("off")
    default: fail("enhanced <pid> read|on|off")
    }

case "hit":
    requireTrust()
    guard let x = Double(arguments[2]), let y = Double(arguments[3]) else { fail("hit <x> <y>") }
    var element: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(x), Float(y), &element) == .success,
          let element else { print("无命中"); exit(4) }
    var chain: [String] = []
    var current: AXUIElement? = element
    for _ in 0..<12 {
        guard let candidate = current else { break }
        let role: String = attribute(candidate, kAXRoleAttribute as String) ?? "-"
        let subrole: String = attribute(candidate, kAXSubroleAttribute as String) ?? "-"
        let title: String = attribute(candidate, kAXTitleAttribute as String) ?? ""
        chain.append("\(role)/\(subrole)\(title.isEmpty ? "" : "「\(title)」")")
        current = attribute(candidate, kAXParentAttribute as String)
    }
    print(chain.joined(separator: " < "))

case "grab":
    requireTrust()
    guard arguments.count > 3, let pid = pid_t(arguments[2]), let element = window(pid, title: arguments[3]),
          let target = frame(of: element) else { print("none"); exit(4) }
    let lights = trafficLights(of: element)
    // 候选点从右往左试：标签条的空白区在右侧，红绿灯与标题文字在左侧。
    // 命中链里出现控件角色就跳过；命中到的窗口必须与目标窗口同帧（不按 CFEqual 判身份）。
    var best: CGPoint?
    for ratio in [0.8, 0.7, 0.6, 0.5, 0.4, 0.3] {
        for depth in [10.0, 18.0, 26.0] {
            let point = CGPoint(x: target.minX + target.width * ratio, y: target.minY + depth)
            if let lights, lights.insetBy(dx: -3, dy: -3).contains(point) { continue }
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
                  let hit else { continue }
            var current: AXUIElement? = hit
            var refused = false
            var hitWindowFrame: CGRect?
            for _ in 0..<12 {
                guard let candidate = current else { break }
                let role: String = attribute(candidate, kAXRoleAttribute as String) ?? ""
                if role == kAXWindowRole as String { hitWindowFrame = frame(of: candidate); break }
                if controlRoles.contains(role) { refused = true; break }
                current = attribute(candidate, kAXParentAttribute as String)
            }
            guard !refused, let hitWindowFrame, close(hitWindowFrame, target, tolerance: 4) else { continue }
            best = point
            break
        }
        if best != nil { break }
    }
    if best == nil {
        let point = CGPoint(x: target.midX, y: target.minY + 6)
        let covering = windowServerEntries(all: false).first { $0.layer < 21 && $0.bounds.contains(point) }
        if let covering, covering.pid == pid, close(covering.bounds, target, tolerance: 2) {
            best = point
        }
    }
    guard let best else { print("none"); exit(4) }
    print("\(Int(best.x)) \(Int(best.y))")

case "drag":
    requireTrust()
    guard arguments.count >= 6, let fx = Double(arguments[2]), let fy = Double(arguments[3]),
          let tx = Double(arguments[4]), let ty = Double(arguments[5]) else {
        fail("drag <fx> <fy> <tx> <ty> [步数] [每步µs] [松手前µs] [--preclick]")
    }
    drag(from: CGPoint(x: fx, y: fy), to: CGPoint(x: tx, y: ty),
         steps: arguments.count > 6 ? Int(arguments[6]) ?? 30 : 30,
         stepMicros: arguments.count > 7 ? UInt32(arguments[7]) ?? 16_000 : 16_000,
         holdMicros: arguments.count > 8 ? UInt32(arguments[8]) ?? 0 : 0,
         preclick: arguments.contains("--preclick"))

case "scroll":
    requireTrust()
    guard arguments.count >= 5, let x = Double(arguments[2]), let y = Double(arguments[3]), let dy = Int32(arguments[4]) else {
        fail("scroll <x> <y> <dy> [步数] [惯性步数]")
    }
    scroll(at: CGPoint(x: x, y: y), dy: dy,
           steps: arguments.count > 5 ? Int(arguments[5]) ?? 6 : 6,
           momentumSteps: arguments.count > 6 ? Int(arguments[6]) ?? 10 : 10)

case "poll":
    requireTrust()
    guard let pid = pid_t(arguments[2]) else { fail("poll <pid> [秒数] [Hz]") }
    let seconds = arguments.count > 3 ? Double(arguments[3]) ?? 5 : 5
    let hertz = arguments.count > 4 ? Double(arguments[4]) ?? 10 : 10
    let started = Date()
    var last = ""
    while Date().timeIntervalSince(started) < seconds {
        let line = axWindows(pid).compactMap { element -> String? in
            guard (attribute(element, kAXRoleAttribute as String) ?? "-") == "AXWindow" else { return nil }
            let subrole: String = attribute(element, kAXSubroleAttribute as String) ?? "-"
            let title: String = attribute(element, kAXTitleAttribute as String) ?? ""
            return "\(subrole)\(trafficLights(of: element) != nil ? "🔴" : "")「\(title.isEmpty ? "-" : title)」"
        }.joined(separator: " ")
        if line != last {
            print(String(format: "t=+%.2fs  %@", Date().timeIntervalSince(started), line))
            last = line
        }
        usleep(UInt32(1_000_000 / max(hertz, 1)))
    }

case "expected":
    requireTrust()
    guard arguments.count >= 5, let x = Double(arguments[3]), let y = Double(arguments[4]),
          let area = visibleAreaInAccessibility(at: CGPoint(x: x, y: y)),
          let rect = normalizedRect(for: arguments[2]) else { fail("expected <zone> <x> <y>") }
    let placed = CGRect(
        x: area.minX + CGFloat(rect.x) * area.width,
        y: area.minY + CGFloat(rect.y) * area.height,
        width: CGFloat(rect.width) * area.width,
        height: CGFloat(rect.height) * area.height
    )
    print(describes(placed))

case "drop-point":
    // 把 zone 名换算成一个可以往那里拖的落点：脚本因此不需要写死"拖到左边"
    requireTrust()
    guard arguments.count >= 5, let x = Double(arguments[3]), let y = Double(arguments[4]),
          let area = visibleAreaInAccessibility(at: CGPoint(x: x, y: y)) else { fail("drop-point <zone> <x> <y>") }
    let whole = wholeDisplayFrame(containing: area) ?? area
    guard let point = dropPoint(for: arguments[2], visible: area, whole: whole) else { print("none"); exit(4) }
    print("\(Int(point.x)) \(Int(point.y))")

case "zones":
    print(snapZones.joined(separator: " "))

case "screen-left":
    requireTrust()
    guard let x = Double(arguments[2]), let y = Double(arguments[3]),
          let area = visibleAreaInAccessibility(at: CGPoint(x: x, y: y)) else { fail("screen-left <x> <y>") }
    print(Int(area.minX))

case "expected-left-half":
    requireTrust()
    guard let x = Double(arguments[2]), let y = Double(arguments[3]),
          let area = visibleAreaInAccessibility(at: CGPoint(x: x, y: y)) else { fail("expected-left-half <x> <y>") }
    print(describes(CGRect(x: area.minX, y: area.minY, width: area.width / 2, height: area.height)))

default:
    print(help)
    exit(2)
}

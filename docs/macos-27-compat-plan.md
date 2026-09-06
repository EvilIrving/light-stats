# macOS 27 (Golden Gate) 兼容性适配 — 实施清单

> 状态：**计划**。本文件仅列出改动点，不含代码实现。
> 关联 issue：#6。分支：`codex/macos-27-compat`。
> 任何改动必须先在此文件确认，再在 macOS 27 真机验证后落地。

---

## 范围

只覆盖风险最高、确定要改的 P0 + P1：

| 项 | 改动 | 文件 |
|----|------|------|
| P0 | 菜单栏权限引导 | `AppDelegate.swift` |
| P1-1 | 窗口菜单图标保留 | `AppDelegate.swift` |
| P1-2 | CGEventTap 权限补齐（Input Monitoring） | `AccessibilityPermission.swift` 等 |

DDC / SMC / Liquid Glass 可读性 / 自动更新属于 P2/P3，等真机验证后再列，不在此文件。

---

## P0 · 菜单栏权限引导

**问题**：macOS 26 起系统设置 → 菜单栏(Menu Bar)需要显式开启 App 的 `NSStatusItem`，否则图标根本不创建。无公开 API 可检测该开关。

**改动点（`Light Stats/AppDelegate.swift`）**：

1. 在 `setupStatusItem()` 创建 `statusItem` 后，探测图标是否真的出现在菜单栏。
   - 探测手段：`NSStatusBar.system.statusItem` 创建后，其 `button` 拿到 `window` 并能在屏幕上取到 frame；若被系统权限拦截，`button.window` 可能长期为 nil 或 frame 不在可见屏幕。可结合一个延时(如 1–2s)检查 `statusItem?.button?.window != nil && statusItem?.button?.window?.isVisible == true`。
   - 注意：**无法区分**「用户手动在菜单栏里隐藏」与「未授权」，两者不可靠区分，只能给出引导而非强提示。

2. 发现图标缺失时，给出**一次性**引导（复用现有权限弹窗机制 `AccessibilityPermission.presentSettingsAlert`，但链接到「菜单栏」设置页）。
   - 菜单栏设置页 URL：`x-apple.systempreferences:com.apple.ControlCenter-Settings.extension`（待真机确认精确 pane）。
   - 文案需新增键，同步到 4 个 `Localizable.strings`。

3. 在 `handleAppDidBecomeActive()`（回到前台）里重查一次，图标恢复后收起引导 / 标记已处理。

**关键约束**：
- 不要每次启动都弹，弹一次并记住（UserDefaults），尊重用户选择。
- 与现有「默认零干扰」原则一致：无授权时不额外发请求、不反复打扰。
- 纯监控用户（未开窗口管理等）也要能进面板 —— 若图标缺失，面板入口没了，这是 P0 最严重的形态问题，必须兜底。

---

## P1-1 · 窗口菜单图标保留

**问题**：macOS 27（link 到 27 SDK）起 `NSMenu` 默认隐藏所有菜单项图片（symbol 与非 symbol），需用新增的 `preferredImageVisibility` 显式保留。

**改动点（`Light Stats/AppDelegate.swift`，`addWindowMenuItem`）**：

```swift
let item = NSMenuItem(title: title, action: ..., keyEquivalent: key)
item.image = WindowSnapIconProvider.icon(for: action)
// macOS 27+：默认隐藏菜单项图片，需显式保留
if #available(macOS 27, *) {
    item.preferredImageVisibility = .always
}
```

- `preferredImageVisibility` 是 macOS 27 新 API，用 `#available` 保护（当前 deployment target 14.6）。
- 只对设置图片的窗口控制菜单项生效；其他不带图片的菜单项不需要。

---

## P1-2 · CGEventTap 权限补齐（Input Monitoring）

**问题**：App 有多个 `CGEventTap`（键盘锁、滚轮反转、找鼠标、标题栏手势、窗口吸附、清洁模式），目前只检测 **Accessibility**（`AXIsProcessTrusted`）。macOS 上部分事件拦截可能还需要 **输入监控(Input Monitoring)** 权限。

**改动点**：

1. **新增输入监控权限检测**（`Light Stats/Services/` 新增一个枚举，类似 `AccessibilityPermission`）：
   - 检测方式：`IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`（`IOKit/hidsystem/IOHIDLib.h`，`IOHIDRequestAccess`）。返回 `kIOHIDAccessTypeGranted` 表示已授权。
   - 也可通过尝试创建 event tap 的返回值侧证。

2. **统一权限检查入口**：每个 tap 服务的 `checkPermission(promptIfNeeded:)` 目前都调 `AccessibilityPermission.isTrusted`，改为同时检查 Accessibility + Input Monitoring：
   - `ScrollDirectionService.swift:145`
   - `WindowSnappingService.swift:51`
   - `KeyboardLockService.swift`、`FindMouseService.swift`、`TitlebarGestureService.swift`、`WindowSnapHotKeyService.swift`

3. **权限提示**：在现有 `AccessibilityPermission.presentSettingsAlert` 基础上，增加指向「输入监控」设置页(`x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`)的引导。

4. **已知风险**：有活跃 tap 时撤销辅助功能权限会导致系统输入卡死（Apple 官方论坛 issue）。确保 `stop()` 在权限变化时被及时调用（现有 `didBecomeActive` 重试机制较稳，需覆盖输入监控被撤销的场景）。

**关键约束**：
- 这些 tap 仍是「默认关闭」——仅在用户开对应开关时才创建。权限检测/提示应保持此语义，不要在清理安装上弹输入监控。
- `checkPermission` 不能做成阻塞弹窗，沿用现有 `promptIfNeeded: false` 静默检测 + 引导的模式。

---

## 已确认不在此范围的项

- **Liquid Glass 菜单栏可读性**：已是 template image 渲染（正确方向），仅需 P2 真机验证 `resolvedFanTintColor()`。
- **DDC 亮度（DisplayControl）**：私有 API，风险高，但与菜单栏权限无关。等 27 真机验证后再单列，且需用户拍板「尽力修」还是「降级隐藏」。
- **SMC / SMAppService / IOPMAssertion / 自动更新**：P2 冒烟项。

---

## 验证

- [ ] mac 27 真机跑一遍：图标出现、面板可开、窗口菜单图标可见、各 tap 生效。
- [ ] 清理安装（空 UserDefaults）无权限弹窗打扰。
- [ ] 四种语言文案齐全（`./script/validate_localization.sh`）。
- [ ] `swiftlint lint --strict` 通过。

---

## 待拍板

1. 是否需要 macOS 27 测试机 / CI 兼容冒烟。
2. DDC 失效时倾向「尽力修」还是「外接屏亮度降级为只读/隐藏」。

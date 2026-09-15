# 06 · 必须替换的东西与已知陷阱

实现前过一遍这一页。每一项都是"如果不提前知道，一定会卡住"的。

---

## 一、私有 API：只有一个，而且用公开路径就能替

| Wins 用了什么 | 用途 | 能不能用公开路径替 |
|--------------|------|------------------|
| `SkyLight.framework` 的 `SLSConnectionGetPID` | 从 Dock 图标的窗口拿到 owner PID | 能：`CGWindowListCopyWindowInfo` 的 `kCGWindowOwnerPID` + `NSRunningApplication` 做映射 |
| WindowServer hover 兜底 | AX 拿不到窗口时的退路 | 能：Wins 日志里 `decision=windowserver-fallback mode=` 说明这就是**降级路径**，用 `CGWindowListCopyWindowInfo` 做兜底即可 |
| `com.apple.WindowManager` / `com.apple.dock` 偏好读写 | 读系统分屏边距、Dock 位置 | 公开：`UserDefaults(suiteName:)`。我们的 `SystemWindowTilingSetting` 已在做 |

**结论：对齐 Wins 的窗口管理，一个私有 API 都不需要。** 二进制里对 SkyLight 的使用只有 1 个符号，且带 dlsym 降级（`sls-symbol-missing` / `sls-owner-pid-failed`）——连他们自己都把它当可选项。这不代表禁用私有 API；只是说**当前这份功能清单走公开路径就能全部做到**，没有必须跨过的槛。

---

## 二、权限

| 权限 | Wins 用来干什么 | 我们的处置 |
|------|---------------|-----------|
| **Accessibility** | 全窗口操作、读 AX 树 | 必需。我们已有 |
| **Screen Recording** | Dock 预览 / Cmd-Tab Plus 的**真缩略图**（`reason=screenRecordingPermission`，跳 `Privacy_ScreenCapture`） | 只有缩略图类功能需要。悬浮分屏岛、边缘吸附、布局全部不需要——岛上的 tile 是矢量图形（`Assets.car` 里的 `Floating*Color`），不是截图 |

二进制里**没有** `CGWindowListCreateImage`、**没有** ScreenCaptureKit 符号，但有 `_screenRecordingGranted` 状态和授权页——所以缩略图必定走系统截图 API 且受该权限门控。

**要做的事**：建一个 `ScreenRecordingPermission`（照抄 `AccessibilityPermission` 的形态）。挂独立子开关还是随总开关、默认开还是关，是**产品选择**，不再是硬约束（AGENTS.md 里“默认零侵入 / 窗口管理无子开关”那两段已移除）。

---

## 三、必须自己写对的三件事（都不是 API 问题，是判断问题）

### 3.1 什么算"一个真窗口"

Wins 用三层过滤，我们目前只有"有没有 frame"这一条 [A]：

```
第一层  子角色白名单：AXStandardWindow | AXDocumentWindow | AXFloatingWindow
第二层  内部黑名单（见 05 文档第五节）+ 正则 ^com\.(jetbrains\.|google\.android\.studio).*?$
        以及进程名 wine64-preloader
第三层  几何/标题启发式：
          skip untitled non-standard window (size=
          skip dialog-like popup (untitled, size=
          skip electron modal widget (title="
          modalwebviewwidget
          AXDialog 角色
```

**不实现这三层的结果**：用户拖动 Chrome 的某个内部弹窗、或某个 App 的工具栏浮层时，我们会对它做吸附，行为不可预测。这是"磕磕绊绊"最密集的来源。

### 3.2 被拖窗口的 CGWindowID 要重试

`SnappingManager` 有 `windowIdAttempt: Int32` 和 `lastWindowIdAttempt: Double?` [A]。
原因：mouseDown 那一刻，AX 树可能还没把窗口标出来，或 `kAXWindowNumberAttribute` 返回 0（我们自己的 `WindowSnappingService.WindowKey` 注释里已经记过同一个坑）。

**要做的事**：把"解析被拖窗口"做成带重试与时间戳的惰性过程，而不是在 mouseDown 里同步取一次。

### 3.3 取窗口 frame 有四条路径

`dragWindowRectAX → dragWindowRectAXFallback → dragWindowRectWindowServer → dragWindowListFallback` [A]。

不同 App 在不同条件下各有各的失败方式。**要做的事**：`WindowFrameResolver` 做成一条链，每级失败记 reason code，最后一级失败就放弃（不要猜）。

---

## 四、必须提前决定的架构选择

### 4.1 摆放：自己写 frame，不走系统菜单项

Wins 四个 mover：`StandardWindowMover`（内含 `bestEffortWindowMover`）、`QuantizedWindowMover`、`BestEffortWindowMover`、`CenteringFixedSizedWindowMover`；`WindowManager` 持有**两条链**：`standardWindowMoverChain` 与 `fixedSizeWindowMoverChain` [A]。

我们现在的 `place()` 是 native-first，代价见主文档。**要做的事**：默认自己摆放；保留"优先系统分屏"作为可选开关。

### 4.2 岛是 `NSPanel`，且必须重写 `constrainFrameRect`

`SnappingIslandWindow : NSPanel`，`canBecomeKeyWindow = false`、`canBecomeMainWindow = false`、`isEditorInteractive: Bool`，并重写 `constrainFrameRect(_:toScreen:)` [A]。

**不重写这个方法的后果**：AppKit 会把面板约束在菜单栏下方，"贴顶"效果做不出来。这是必踩的坑，提前知道就省一天。

### 4.3 动画自己插值，不用 `window.animator()`

见 `04-behaviour-spec.md`。`SnappingIslandWindowAnimator` 是 Timer + `startTime` + `didFinish` + `onFrameUpdate` [A]。

### 4.4 岛的三态而不是两态

`SnappingIslandState { collapsed, open }` + `SnappingIslandTransition { show, expand, collapse, hide, resize }` [A]。
**`resize` 是必须单独处理的一个**：换屏、换布局时原地改尺寸，不能重放 show。漏了这条会看到岛在换屏时闪一下。

### 4.5 还原要区分"上次是谁动的"

`WindowHistory { restoreRects, restoreCenterRects, lastRectangleActions, lastSystemActions }` [A]。
`ExecutionParameters.updateRestoreRect: Bool` —— 是否覆盖还原点是一个显式参数。

---

## 五、系统集成点（要持续观察，不是一次性调用）

| 观察对象 | Wins 里的痕迹 | 为什么必须观察 |
|---------|--------------|--------------|
| 屏幕变化 | `screenObserver`、`displayConfigurationRetryDelay`、`Display` 结构体带 `uuid` | 显示器插拔会重置可见区域与 Dock 位置 |
| Dock 偏好 | `com.apple.dock.prefchanged`、`isObservingDockPreferences`、`observedDockPID`、`DockPreferences` | Dock 的自动隐藏/位置会改变可用区域 |
| 登录/解锁 | `com.apple.screenIsUnlocked`、`com.apple.loginwindow`、`unlockObserver` | 解锁后显示器配置与 Dock 状态可能变 |
| 台前调度 | `StageUtil`、`respectStageManager`、`drag.stageManager` 阶段 | 台前调度会动态改变窗口可用区域 |
| 系统自带分屏 | `tiledMarginsMonitorTimer`、`lastObservedSystemTiledMargins`、`isApplyingMarginFromSystem` | **避免自家间距与系统间距叠加** |
| Workspace 通知 | `WorkspaceEvents`、`AppActivationTracker`、`AppActivationRecord` | 前台 App 变化影响"动作作用在哪个窗口" |
| AX 通知 | `AXObserver` + 上表那一串 `AXWindow*` 通知 | 比轮询便宜得多 |

**最容易漏的一条**：`isApplyingMarginFromSystem`。macOS 15+ 的系统分屏会自己加边距，我们如果也加，用户会看到双倍间距。

---

## 六、OS 版本差异（实测存在的分支）

```
mode=macos27 result=ordered-front windowNumber=
mode=macos27 result=no-op-same-visible windowNumber=
mode=legacy windowNumber=
dock-observer result=skipped reason=macos-27 pid=
reason=notInCGS
```

**[B]**：在 macOS 27 上，(a) 窗口置前的行为变了，(b) **Dock 观察者被整个跳过**。

对我们的意义：我们的目标是 macOS 14+，实际会跑在 26/27 上。做 Dock/窗口置前相关功能时必须实测两个版本，不能假定行为一致。

---

## 七、会互相打架的第三方

`com.west2online.ClashX`、`io.github.clash-verge-rev.clash-verge-rev` 出现在黑名单里，说明**代理类工具会干扰**（它们有自己的全局事件处理）。
更普遍的问题是：**用户同时装 Magnet / Rectangle / Wins / 我们的 App**。Wins 用黑名单 + 系统分屏边距观测来缓解；我们应该：
1. 启动时检测已知的同类工具（`NSWorkspace.shared.runningApplications` 按 bundle id），若在跑就提示"可能冲突"。
2. 我们自己的边缘触发开启时，关掉系统自带的边缘拖拽（`SystemWindowTilingSetting` 可写）。

---

## 八、我们当前代码里已经确认的问题（趁这次一起修）

| 问题 | 位置 | 证据 |
|------|------|------|
| restore 在原生路径丢原始 frame | `WindowSnappingService.place` / `snap` | `saveFrameIfNeeded` 只在 `snap()` 里调用；`performNatively` 成功时提前 `return .moved("native")` |
| 取窗口 frame 只有一条路径 | `WindowSnappingService.frame(of:)` | 没有 fallback 链 |
| 预览只有 alpha，无几何插值 | `WindowSnapPreviewService` | `setFrame(frame, display: true)` 是硬跳 |
| 快捷键 6/19，硬编码 | `WindowSnapHotKeyService.defaultHotKeys` | `static let` |
| 没有窗口拖动监听 | 全仓 | 只有 `TitlebarGestureService` 的 scrollWheel tap |
| 没有窗口资格过滤 | `WindowSnappingService.canPlace` | 只判断有没有 frame |
| 没有事件监听工具类 | `AppDelegate` / 两处 Settings | Wins 有 `EventMonitor { globalMonitor, localMonitor, mask, handler }` 统一封装 |
| 没有 AX 串行队列 | — | Wins 有 `accessibilityCommandsQueue`，注释明确说"有并发上限且返回前同步等待" |

最后两条尤其值得抄：**`EventMonitor`** 是个 20 行的小工具，能消掉我们三处重复的 monitor 代码；**AX 串行队列**是拖动期间不掉帧的前提。

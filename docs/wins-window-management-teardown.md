# 目标：对齐 Wins —— 窗口管理拆解、差距诊断与实施路线图

> 状态：调研完成（2026-09-14）。基于本机 Wins 3.5.1 与 `~/Downloads/Wins-latest.dmg` 的实测拆解。
>
> **完整档案在 `docs/wins-teardown/`**：安装包清单 / 功能矩阵 / 190 个类的字段表 / 行为规格 / 键与资产 / 陷阱清单。本文是差距诊断与路线图，实现细节一律以档案为准。
>
> 结论先行：Wins 只 dlsym 了一个 SkyLight 符号（`SLSConnectionGetPID`，用于 Dock 图标反查进程），其余建立在 Accessibility + AppKit + Core Animation 之上。所以“对齐 Wins”不是技术封锁问题，是**我们自己几条规则把上限焊死了**：
>
> 1. **native-first** 把摆放能力钉死在系统 Window 菜单项上（没有三分屏、没有间距、没有自定义布局，且要等 600 ms 才知道成没成）；
> 2. **动作是 enum、快捷键是常量**（19 个 action，只有 6 个有快捷键，用户不能改、不能加）；
> 3. **没有任何窗口拖动监听**（只有标题栏滚动手势），所以“拖到边缘”这条最主要的入口根本不存在；
> 4. 预览只有 alpha 淡入，没有几何插值；
> 5. **自我禁用的私有 API**——产品做得好优先，可用的能力没有理由不用。
>
> 要达到对齐，必须换掉 1、2、3。1 是架构决策（我们主动写了"窗口管理交给系统"），不是能力缺失。

---

## 一、证据来源

| 来源 | 路径 | 得到什么 |
|------|------|---------|
| 安装包 | `~/Downloads/Wins-latest.dmg` (57.2 MB, UDIF/zlib) | DMG Canvas 制作：`.background/dmgcanvas_bg.tiff`、`.VolumeIcon.icns`、Applications 软链 |
| 主程序 | `/Applications/Wins.app/Contents/MacOS/Wins` (6.2 MB, x86_64+arm64) | 197 个 Swift 类、链接框架、entitlements |
| 反射元数据 | `__TEXT,__swift5_reflstr`（offset 2274048, size 0x5d6b） | 全部 Swift 属性名（含私有），本次拆解的主要情报源 |
| ObjC 元数据 | `otool -oV` | 类名、父类、ivar 名字与声明顺序（`offset` / `size` 两列对 Swift 类不可靠，已弃用） |
| 设置面板 | `Contents/Resources/Wins.prefPane` | 全部功能开关 + 20 段功能演示 MP4 |
| 官网/用户截图 | 用户提供 | 六条卖点（含"动画是软件的灵魂"） |

Wins 的 Swift 符号表被 strip（`nm -a` 为 0），但反射段保留属性名，足以还原数据模型。
下面凡是我从字段组合推出的结论，都标 **【推断】**；其余为直接读出的**事实**。

---

## 二、Wins 的完整功能面

`LSUIElement = 1`，**没有 Dock 图标、没有菜单栏图标、没有独立设置窗口**——设置以 `.prefPane` 挂在系统设置里。授权 Paddle + Sparkle，非沙盒（`app-sandbox = false`、`allow-jit = true`、`automation.apple-events = true`、`NSAllowsArbitraryLoads = 1`）。

| 分组 | 功能 | 我们的现状 |
|------|------|-----------|
| **分屏** | 屏幕边缘分屏、**悬浮分屏岛**、分屏窗口间距、**窗口布局（可编辑）**、窗口居中 | 边缘/角/三分/跨屏/最大化/还原有；间距、布局、悬浮岛无 |
| **快捷** | 上/下个显示器、隐藏所有窗口、隐藏其他窗口、**摇动窗口**、调度中心 Pro（关闭窗口/退出程序快捷键） | 跨屏有；隐藏/摇动/调度中心无 |
| **Dock** | Dock 窗口预览（缩略图）、Dock 窗口反转、Dock 锁定屏幕 | 无 |
| **切换器** | Cmd-Tab Plus（替换系统切换器，带缩略图） | 无 |
| **全局** | 排除 App（不响应快捷键与分屏）、强调色、预留台前调度空间 | 排除列表、台前调度避让无 |

---

## 三、动画是怎么做的（核心）

### 3.1 自研逐帧插值器，而不是 `window.animator()`

`SnappingIslandWindowAnimator` 的 ivar（ObjC 元数据，ivar 名与声明顺序可靠；字节大小列不可靠，故省略）：

```
window            NSWindow?
startFrame        CGRect
targetFrame       CGRect
topAnchorY        Double
startAlpha        Double
targetAlpha       Double
motion            SnappingIslandTransition   // 枚举：show/expand/collapse/hide/resize
onFrameUpdate     闭包
completion        闭包
timer             Timer?
startTime         Double
didFinish         Bool
```

配对参数结构体（同段反射字符串）：`response`、`dampingFraction`、`duration`、`timingFunction`。

**读法【推断，依据 ivar 组合 + 参数命名】**：Timer 驱动的逐帧插值——每帧算 `progress`，用 `response`/`dampingFraction`（SwiftUI 弹簧语义）或 `duration`+`timingFunction`（曲线语义）求 0→1 进度，线性插值 `frame` 与 `alpha`，经 `onFrameUpdate` 写回 `NSWindow`，结束调 `completion`。

**为什么不用 `window.animator()`**：那套时长与曲线固定，且**中间帧拿不出来**。投影岛需要在中途同时更新圆角、阴影进度、内容布局，还要能被下一次输入打断。

### 3.2 运动是状态机，不是"打开/关闭"

`SnappingIslandTransition` 的 case：**`show` / `expand` / `collapse` / `hide` / `resize`**。

> 命名注意：**`SnappingIslandTransition` 是过渡类型，`SnappingIslandMotion` 是参数结构体**（`response` / `dampingFraction` / `duration` / `timingFunction`），容易看反。另有一个 `SnappingIslandState { collapsed, open }` 表示静止态。

- 拖到顶部 → `show`（折叠条出现）
- 悬停/继续 → `expand`（展开出布局 tile）
- 离开 → `collapse`（缩回折叠条）
- 放弃 → `hide`
- 屏幕变化/换布局 → `resize`（原地改尺寸，不重放 show）

印证字段：`topAnchorY`（动画期间**上边缘钉住**，岛从顶部长出来）、`collapsedPreviewTopRatio`、`topOverflowTolerance`、`centerActivationWidthRatio`。

### 3.3 外观过渡是显式进度量

协作对象挂着：`shadowProgress`、`topCornerRadius`、`bottomCornerRadius`、`topSeamGuardHeight`、`showsShadow`，协调器里有 `_visualOpenProgress`。

**一个 0→1 的 openProgress 同时驱动圆角插值、阴影透明度、顶部接缝预留高度**。贴顶两角与下面两角圆角分开设置。这是"看起来贵"的具体来源。

### 3.4 窗口帧与图层效果走两条路

- **窗口本体**（frame/alpha）：自研插值器 + `setFrame:display:`、`setFrameOrigin:`
- **图层效果**（缩略图、Dock 预览、调度中心）：`NSAnimationContext` + Core Animation（`addAnimation:forKey:`、`animationWithKeyPath:`、`CAMediaTimingFunction`、`setCornerRadius:`）
- **实际落位**：也用到了 `setFrame:display:animate:`

这和我们 `confirmNativePlacement` 的"等 600 ms 再读回"是同一约束的两面：窗口动画期间读到的 frame 不可信。

### 3.5 Reduce Motion 是一等参数

关闭窗口的粒子爆散动画有一整组参数，其中 `reduceDuration` 单独存在：

```
totalDuration, reduceDuration, overshootScale, collapseScale,
hideOriginalDuringAnimation, originalViewDimmedAlpha,
fadeOutCurve, scaleOutCurve,
enableParticles, particleCountMean/Range/Lifetime/Velocity/EmissionRange,
particleUpwardBiasDeg, highlightFraction, particleScaleRange, burstPulse,
totalParticleCount, explosionStrength, enableHighQualityTextures
```

**"减少动态效果"不是关掉动画，是换一条更短的时间线。** 我们完全没做。

---

## 四、触发与判定

- `SnappingIslandActivationDetector`：`topOverflowTolerance`、`horizontalTolerance`、`collapsedPreviewTopRatio`、`centerActivationWidthRatio`
- `SnapAreaDetector`：`marginTop/Bottom/Left/Right`、`ignoredSnapAreas`、`snapOptionToAction`；另有 `cornerSnapAreaSize`
- **间距同时作用于落位几何与触发区域**（`GapCalculation`、`applyGapsToMaximize`、`applyGapsToMaximizeHeight`）——预览框与最终落位天然一致
- **动作计算类 62 个、用户可见布局只有 4 个**：`WindowCalculationFactory` 产出 62 个 `*Calculation`（含 `FirstThird`/`CenterThird`/`LastThreeFourths`/`MiddleCenterNinth`、`AlmostMaximize`、`MaximizeHeight`、`ChangeSize`、`Specified`、`*Landscape`/`*Portrait` 变体），但实测 `snappingIslandLayouts` 里**只有 4 个内置布局**：`Halves` / `Thirds`（其实是 2/3+1/3）/ `Right Stack` / `Quadrants`。**计算类 ≠ 用户可见布局**
- **移动策略链**：`StandardWindowMover`、`QuantizedWindowMover`（终端类按字符格移动）、`BestEffortWindowMover`、`CenteringFixedSizedWindowMover`（小于目标矩形不拉伸，改居中）
- **取消可还原**：`UnsnapRestorer` + `WindowHistory` + `SnappingIslandSavedPlacementStore`
- **取窗口 frame 有四条路径**：`dragWindowRectAX` → `AXFallback` → `WindowServer` → `WindowListFallback`
- **被拖窗口的 CGWindowID 带重试**：`windowIdAttempt` + `lastWindowIdAttempt`，因为 mouseDown 那一刻 AX 常常还拿不到标识
- **什么算"一个真窗口"有三层过滤**：AX 子角色白名单（`AXStandardWindow`/`AXDocumentWindow`/`AXFloatingWindow`）→ 内置黑名单（35 个 bundle id + 一条匹配全部 JetBrains/Android Studio 的正则 + `wine64-preloader` 进程名）→ 几何/标题启发式（无标题非标准窗口、无标题弹窗、Electron 的 `modalwebviewwidget`）
- **`AXEnhancedUserInterface` 必须打开**，否则 Electron / Java 类 App 的 AX 树几乎是空的
- **与系统分屏共存**：`tiledMarginsMonitorTimer`、`lastObservedSystemTiledMargins`、`isApplyingMarginFromSystem`、`respectStageManager`——**观测系统施加的边距，避免自家间距叠加**

---

## 五、权限与代价

| 项 | Wins | 对我们的含义 |
|----|------|-------------|
| Accessibility | 必需 | 我们已是 opt-in，一致 |
| **Screen Recording** | **必需**，有专门授权页（`_screenRecordingGranted`、`reason=screenRecordingPermission`、跳 `Privacy_ScreenCapture`） | 缩略图类功能的唯一前提（Dock 预览、Cmd-Tab Plus）。我们目前没有 |
| 私有 API | 仅 SkyLight `SLSConnectionGetPID`（dlsym + 降级） | 对齐不依赖它，但**不再自我禁用**：需要时按收益单独评估（WindowServer 层窗口解析、缩略图等） |
| 沙盒 | 关闭 | 保持现状 |
| 资源声明 | 内存 < 40 MB、CPU < 10%、常态 0.1% | 用我们已有的 `PerformanceLogService` 量 |

二进制里**没有** ScreenCaptureKit 符号，也**没有** `CGWindowListCreateImage`——缩略图能力确实挂在 Screen Recording 授权之后，与"未授权即拿不到"自洽。

---

## 六、差距诊断：为什么我们的窗口管理几乎不可用

### 6.1 根因一：native-first 把能力上限焊死在系统菜单项上

`WindowSnappingService.place(_:on:processID:)` 的第一条分支就是 `NativeTilingCommand.matching(action)` → `performNatively` 成功即返回 `.moved("native")`。

代价（我们自己的 AGENTS.md 已经记录了前两条）：
- 系统菜单项**在前台 App 不是目标 App 时也报成功，然后什么都不做**；
- 系统用真实移动做动画，结果要 ~600 ms 后才读得到（`confirmNativePlacement`）；
- 系统**没有**三分屏、没有间距、没有自定义布局、没有悬浮岛；
- 命中率不足时要走 600 ms 超时兜底 → 单次操作 600 ms 延迟。

Wins 完全不做这件事：它**自己摆放**（4 个 mover），系统那套只是可选加速。

### 6.2 根因二：动作是 enum，快捷键是常量

- `WindowSnapAction`：19 个固定 case
- `WindowSnapHotKeyService.defaultHotKeys`：`static let`，6 个（←→↑↓、Return、C）

**键盘可达率 6/19 ≈ 32%**，其余只能点菜单栏；用户不能改键、不能加动作、不能保存自己的布局。
Wins 的快捷键是用户可录制的（KeyboardShortcuts），布局是数据（JSON）。

> 我们其实已有录制器的先例：`CleanupPanelHotKeySettingsSection`（`NSEvent.addLocalMonitorForEvents(matching: [.keyDown])` → `PanelHotKey`）与 `FindMouseTriggerRecorder`。不需要第三方依赖。

### 6.3 根因三：没有窗口拖动监听

全仓只有三处事件监听：`AppDelegate` 的两次点击监听、`FindMouseTriggerRecorder`、`CleanupPanelHotKeySettingsSection`。窗口相关只有 `TitlebarGestureService` 的 **scrollWheel** tap。

**结果："拖动窗口到屏幕边缘"这条最主要、最直觉的入口根本不存在。** 用户必须知道"在标题栏上双指滑动"。Wins 直接监听窗口拖动本身（`MouseMovementMonitor`、`globaleMouseLoc`）。

### 6.4 根因四：预览只有淡入淡出

`WindowSnapPreviewService` 只有 `animator().alphaValue`，`setFrame` 是硬跳。没有几何插值、没有可中断、没有 reduce-motion 分支。

### 6.5 根因五（已确认的 bug）：restore 在原生路径丢原始 frame

`saveFrameIfNeeded` 只在 `snap(_:action:)` 里调用，而 `place(...)` 在 `performNatively` 成功时**提前返回**，永远走不到 `snap`。

后果：**凡是用系统分屏路径吸附过的窗口，`restore` 无原始 frame 可回**（`canPerform(.restore)` 返回 false，菜单项变灰）。

### 6.6 根因六：没有间距、排除列表、布局、窗口列表

无 gap/margin；无"排除 App"；无自定义布局；菜单栏菜单里列出不了窗口（只能对"当前窗口"发动作）。

### 6.7 我们那几条规则现在该怎么处理

| 既有规则 | 出处 | 处置 |
|---------|------|------|
| "Window management delegates to the system. Native-first" | AGENTS.md Layer Contracts | **改**。默认改为自己摆放；native 降级为可选的"优先走系统"开关（给想要系统动画/系统规则的场景）。这是本次最大的一条架构变更 |
| "No private API as a shortcut"（隐含） | 工程判断 | **删掉**。产品做得好优先；私有能力按收益与稳定性单独评估，不做全局禁用 |
| "默认零侵入：不做任何网络/权限请求" | AGENTS.md Default form | **删掉**（整节已移除）。窗口管理仍是单一 master switch，但这是架构选择不是禁则；权限何时申请按产品需要定 |
| "Zero third-party dependencies" | AGENTS.md | **删掉**。不再是禁则；需要哪个依赖就用，按收益评估 |
| "Logic only, never UI tests" | AGENTS.md Test policy | **保留并且正好是路线图的组织方式**：每个判定都拆成纯类型（policy / geometry / curve / model） |
| "One type per file / file_length 800 / function_body_length 90" | AGENTS.md Style | **保留**。62 个动作计算类换到 Swift 里不能一个文件塞完，要用数据表 + 通用几何求解，而不是照搬类爆炸 |

改 AGENTS.md 时记得 **`CLAUDE.md` 是镜像，两边必须同步改**。

### 6.8 除了功能缺失，还有 14 件必须提前做对的事

这些都不是"功能"，而是不做就会在实现中途卡住、或者做完看起来能跑但行为不可预测的东西。全部来自拆解档案，届时对着查。

| # | 事项 | 不做的后果 | 出处 |
|--:|------|-----------|------|
| 1 | **窗口资格三层过滤**：AX 子角色白名单 → 内置黑名单 → 几何/标题启发式 | 对 Chrome 内部弹窗、工具栏浮层做吸附，行为不可预测 | §四 |
| 2 | **内置风险 App 黑名单**（35 个 bundle id + 匹配全部 JetBrains 的正则 + `wine64-preloader`） | 播放器断播放、游戏/反作弊异常、远程桌面卡死 | §六、05 档案 |
| 3 | **被拖窗口 ID 带重试**（`windowIdAttempt` + 时间戳） | mouseDown 那一刻 AX 常常拿不到标识或返回 0，拖动全程找不到窗口 | §四 |
| 4 | **取 frame 走四路降级链**（AX → AX fallback → WindowServer → WindowList） | Electron / Java / 游戏窗口在某一条件下失败就没有退路 | §四 |
| 5 | **打开 `AXEnhancedUserInterface`** | Electron / Java / 部分游戏的 AX 树几乎是空的——这正是我们现在在 Electron 上不准的可能原因 | 05 档案 §四 |
| 6 | **AX 调用串行队列**（`accessibilityCommandsQueue`，有并发上限且返回前同步等待） | 拖动时与采集任务抢 AX，掉帧 | §八 |
| 7 | **岛必须重写 `constrainFrameRect(_:toScreen:)`** | AppKit 把面板约束到菜单栏下方，“贴顶”做不出来 | §四 |
| 8 | **岛是三态不是两态**（`.collapsed/.open` + `show/expand/collapse/hide/resize`） | 换屏时岛会闪一下（`resize` 被当成重新 show） | §四 |
| 9 | **还原要区分上次是谁动的**（`lastRectangleActions` vs `lastSystemActions`） | 用户手拖过窗口后，我们用自己的旧 rect 去“还原”，把窗口投回奇怪位置 | §六 |
| 10 | **还原点是否更新是显式参数**（`updateRestoreRect: Bool`） | 连续吸附会覆盖真正的原始 frame，失去还原能力 | §六 |
| 11 | **与系统分屏边距协同**（观测系统已施加的边距，不叠加） | 开间距后用户看到双倍间距 | §五 |
| 12 | **OS 版本分支实测**（macos27 窗口置前行为不同、Dock 观察者在 27 上被跳过） | 在新系统上行为静默错位 | §五 |
| 13 | **坐标 y 轴方向统一**（岛布局 JSON 是归一化 + **y 轴向上**；`ExecutionParameters` 里用 `NSScreen`） | 整体上下镜像，且只在多屏/非主屏暴露 | 02 档案 §六 |
| 14 | **性能插桩记录 max 而不只是平均**（`TimingStats.maximumNanoseconds`，帧预算 16 ms） | 拖动卡顿是瞬时事件，平均值会掩盖它 | §十 |

另外两件值得直接抄的小东西：`EventMonitor { globalMonitor, localMonitor, mask, handler }`（我们目前三处手写 monitor，可归并）；`*VerboseLog` 式的**逐子系统日志开关**（默认关，出问题时单独开）。

---

## 七、目标架构

### 7.1 摆放层：自己摆放为默认

```
WindowSnappingService（保留，改为编排）
 └── WindowPlacementEngine          写 frame 的唯一出口，记录 achieved frame 并校验
      ├── NativeTilingAccelerator   可选：优先按系统 Window 菜单项（用户开关）
      ├── StandardPlacement         直接写 AX position/size
      ├── QuantizedPlacement        终端/网格窗口：按字符格量化 【对齐 Wins 的 QuantizedWindowMover】
      └── CenteredPlacement         小于目标矩形不拉伸，改居中 【CenteringFixedSizedWindowMover】
 └── UnsnapRestorer                 每次吸附前记录真实原始 frame，两条路径都记（修 6.5）
```

### 7.2 动作层：数据化

```swift
// Models/SnapLayout.swift —— 全部 Codable + Sendable，可单测
struct SnapSegment: Codable, Hashable, Sendable { var column, row, width, height: Int }
struct SnapLayout:  Codable, Hashable, Sendable {
    var id: String; var title: String; var isBuiltIn: Bool; var segments: [SnapSegment]
}
enum SnapTarget: Sendable { case layout(SnapLayout, segment: Int)
                            case rect(CGRect)          // 自定义矩形
                            case display(Int)          // 跨屏
                            case maximize, almostMaximize, center, restore, minimize }
```

`SnapLayoutCatalog`（纯类型）内置整套：halves / quarters / thirds / fourths / sixths / eighths / ninths + 横竖屏变体 + `almostMaximize`。
**不用 62 个类**——用"网格坐标 + 通用几何求解"（`column/row/width/height` → CGRect），一个函数覆盖全部，测试覆盖网格边界即可。Wins 的类爆炸是历史包袱，不是优点。

**而且实测他们的用户可见布局只有 4 个**（Halves / Thirds / Right Stack / Quadrants）。我们的目标应该是：内置 4–6 个**预设布局**（等价物），加上用户能自己拉网格造布局——而不是把 62 种几何全部暴露给用户。

### 7.3 感知层：拖动监听 + 双路解析

```swift
@MainActor final class WindowDragMonitorService {   // Shape C，start()/stop()
    // CGEventTap 监听 leftMouseDown/Dragged/Up
    // 拖动中每帧：读被拖窗口 AX frame → 交给纯策略 → 输出 candidate target
}
nonisolated enum SnapZonePolicy {                   // 纯类型，全测
    static func target(dragFrame: CGRect, screen: CGRect,
                       margins: SnapMargins, ignoredAreas: Set<SnapArea>,
                       islandConfig: IslandConfig) -> SnapZoneResult
}
```
`SnapZoneResult` = `.edge(SnapTarget)` / `.island(collapsed | expanded)` / `.corner(SnapTarget)` / `.none`。

### 7.4 表现层：动画引擎

```swift
// Utilities/SnapAnimationCurve.swift —— 纯类型，全测
struct SnapSpring { var response: Double; var dampingFraction: Double }   // SwiftUI 语义
enum SnapTiming { case spring(SnapSpring), curve(CAMediaTimingFunctionName, duration: TimeInterval) }
struct SnapAnimationPlan { var startFrame, targetFrame: CGRect; var topAnchorY: CGFloat?
                           var startAlpha, targetAlpha: Double
                           var motion: SnapMotion      // show/expand/collapse/hide/resize
                           var timing: SnapTiming
                           func sample(at t: TimeInterval) -> (frame: CGRect, alpha: Double, progress: Double) }
```
配 `SnapAnimationDriver`（`CADisplayLink`/`CVDisplayLink` 驱动）→ 逐帧写 `NSWindow.frame` + alpha + 圆角 + `shadowProgress`。
**Reduce Motion 走 `SnapAnimationPlan.reduced`**（更短的时间线，不是关闭）。

- `WindowSnapPreviewService` 重写为用这套管线
- 新增 `SnapIslandWindow`（`NSPanel`，`canBecomeKeyWindow = false`，`ignoresMouseEvents = true`，编辑态才放开，**必须 override `constrainFrameRect(_:to:)`**，否则被压在菜单栏下——Wins 的 `SnappingIslandWindow` 正好重写了这一个，方法签名 `{CGRect}56@0:8{CGRect}16@48` 与之吻合）
- 新增 `SnapIslandController`（Shape C）+ SwiftUI 内容

### 7.5 交互层：网格选择器 + 布局编辑器 + 保存位置

参考 Wins 的 ivar 即规格：`_layouts`、`_savedPlacements`、`_currentSize`、`_hoveredType`、`_hoverLocation`、`_draggingActiveLayoutID`、`_invalidDropTargetID`、`_highlightedDropTargetID`、`_draftLayout`；动作 `addLayout`、`deleteActiveLayout`、`deleteActiveSegment`、`moveActiveLayout`、`resetLayouts`、`deleteSavedPlacement`、`moveSavedPlacement`、`createActiveLayoutFromSavedPlacement`。

网格选择器是 8×8 拖拽选区（`gridSize`、`previewSize`、`onPreview`、`onCommit`、dragStart/Current/HoverCell），编辑态有 jiggle。

本层只消费 7.2 的数据模型，全是 Codable + 纯几何 → 单测覆盖。

### 7.6 预览层：窗口列表 → 缩略图

- **不依赖权限的版本**：菜单栏窗口菜单里列出当前 App 的所有窗口（标题 + 图标，AX 可读），可聚焦/最小化/关闭。零新权限。
- **缩略图版本**：独立开关（默认关），用户显式开启时才申请 Screen Recording（新建 `ScreenRecordingPermission`，复用 `AccessibilityPermission` 的模式），用 ScreenCaptureKit（`SCScreenshotManager` / `SCStream`）；公开路径受限时，私有路径也在可用选项内。
- Dock 预览 / Cmd-Tab Plus 属于同一层，见路线图 M6。

### 7.7 快捷键：可录制

`WindowSnapHotKey` 增加"无键"状态 + `SnapCommand` 稳定 ID；设置页复用 `CleanupPanelHotKeySettingsSection` 的录制逻辑，泛化成一个 `KeyComboRecorder`。动作覆盖到全部 19+ 项。

### 7.8 新增文件清单（对齐现有分层）

```
Models/       SnapLayout.swift  SnapSegment.swift  SnapTarget.swift  SnapLayoutCatalog.swift
              SnapMargins.swift  SnapArea.swift  SnapIslandConfig.swift
              SnapMotion.swift  SnapAnimationPlan.swift（或放 Utilities）
Utilities/    SnapAnimationCurve.swift  SnapGridGeometry.swift  SnapAnimationDriver.swift
Services/     WindowPlacementEngine.swift  QuantizedPlacement.swift  CenteredPlacement.swift
              WindowDragMonitorService.swift  SnapZonePolicy.swift（nonisolated）
              SnapIslandController.swift  SnapIslandWindow.swift
              SnapLayoutStore.swift  SnapSavedPlacementStore.swift
              SnapExclusionStore.swift  SnapPreviewWindowService.swift（重构）
              ScreenRecordingPermission.swift  WindowThumbnailService.swift
ViewModels/   SnapLayoutEditorModel.swift  SnapIslandViewModel.swift
Views/…       SnapIslandView.swift  SnapLayoutEditorView.swift  SnapWindowListView.swift
LightStatsTests/  SnapZonePolicyTests  SnapIslandPolicyTests  SnapAnimationCurveTests
                  SnapLayoutCatalogTests  SnapGridGeometryTests  SnapMarginsTests
                  SnapPlacementEngineTests  SnapSavedPlacementTests
```

---

## 八、分阶段路线图

每个里程碑独立可合入、可验证，且严格依赖前一步。

### M0 — 止血（把"不可用"拉回"能用"）

| 项 | 交付 |
|----|------|
| 修 6.5 | `saveFrameIfNeeded` 上提到两条路径共用；加回归测试 |
| 删 600 ms | 自己摆放为默认路径，native 改为可选开关；预览→落位不再二次等待 |
| **窗口资格过滤** | `SnapWindowEligibility`（纯类型）：AX 子角色白名单 + 内置风险 App 黑名单 + 几何/标题启发式（6.8 的 1–2） |
| **frame 降级链** | `WindowFrameResolver`：AX → AX fallback → CGWindowList → 放弃，每级记 reason code（6.8 的 4） |
| **被拖窗口 ID 重试** | 带 `attempt` + 时间戳的惰性解析（6.8 的 3） |
| **AX 串行队列** | `AXCommandQueue`，拖动与采集共用（6.8 的 6） |
| 加间距 | `SnapMargins`（四边）+ `SnapGridGeometry` 内缩；**间距同时内缩触发区**；先读系统分屏边距避免叠加（6.8 的 11） |
| 加排除列表 | `SnapExclusionStore`（bundle id），命中即不响应快捷键与分屏；内置黑名单可关闭（6.8 的 2） |
| 小工具 | `EventMonitor` 统一封装三处手写 monitor；`AXEnhancedUserInterface` 开关（6.8 的 5） |

验收：19 个动作全部有快捷键路径；吸附后 `restore` 100% 可回；间距与预览框一致；对 Electron / 系统弹窗 / 黑名单 App 不做误吸附（逐类有单测）；单测全绿。
**不需要任何新权限。**

### M1 — 动画与预览（对齐 Wins 的"丝滑"）

`SnapAnimationCurve` + `SnapAnimationPlan`（纯类型，全测）→ 重写 `WindowSnapPreviewService` 走逐帧几何插值 + 可中断 + reduce-motion。

验收：预览框从当前窗口 frame 生长到目标 frame；中途换方向反向插值而非重开；开启"减少动态效果"后时间线变短而非消失。

### M2 — 拖动到边缘（对齐 Wins 的"快速分屏"）

`SnapZonePolicy`（纯类型 + 全测）→ `WindowDragMonitorService`（Shape C，`CGEventTap` 监听鼠标拖动）→ 复用 M1 的预览管线 → 提交走 M0 的摆放引擎。

**必须同时处理**：开启我们的边缘触发时关闭系统自带的边缘拖拽（`SystemWindowTilingSetting` 已能写），设置里说明二选一。

验收：任意窗口（含 Electron / 自绘标题栏）拖到边缘出现 footprint；松手落位；与系统分屏不叠加。

### M3 — 顶部悬浮分屏岛（招牌功能）

- `SnapIslandPolicy`（纯类型）：拖 frame + 屏幕 → `.collapsed(stripRect)` / `.expanded(rect)` / `.none`
- `SnapIslandWindowAnimator`（纯类型）：`SnapAnimationPlan` + `SnapMotion` 状态机，假时钟注入可测
- `SnapIslandWindow` + `SnapIslandController`（Shape C）
- 岛内容：内置布局 tile，落下即执行

验收：拖到顶部中央 → 折叠条（`collapsedPreviewTopRatio`）→ 展开 → 悬停高亮 → 落下；离开自动 collapse/hide；`resize` 不重放 show；关掉 master switch 立即销毁面板。

### M4 — 布局数据化 + 网格选择器 + 保存位置

`SnapLayout` 全量内置目录（halves…ninths + 横竖变体 + almostMaximize）→ 网格选择器（8×8 拖选）→ 布局编辑器（增删/移动/重置）→ `SnapSavedPlacementStore`（JSON 持久化）→ 快捷键可录制。

验收：用户能造一个内置目录里没有的布局并赋快捷键；重启后仍在；`SnapLayoutCatalog` 边界全测。

### M5 — 附加能力对齐

摇动窗口隐藏其他窗口（`DragShakeChecker` 纯函数）、隐藏所有窗口、调度中心 Pro 式"关闭窗口/退出程序"快捷键、台前调度避让、强调色。

### M6 — 窗口预览与切换器（需 Screen Recording）

窗口列表（零权限）→ 缩略图（`ScreenRecordingPermission` 独立开关 + ScreenCaptureKit）→ Dock 悬停预览 → Cmd-Tab Plus。

**M6 每一项独立开关。** 是否默认关按产品判断，不再有全局清单约束。

---

## 九、风险与仍需你拍板的事

**技术上没有封锁**，但有三件事需要你明确：

1. **摆放默认路径改成"自己摆放"** —— 这会改掉 AGENTS.md 里 "Window management delegates to the system" 那条契约（含 `CLAUDE.md` 镜像）。系统原生分屏的动画与多屏可见区规则会失去，换来三分屏/间距/自定义布局/岛。建议：默认自己摆放，但保留一个"优先使用系统分屏"开关给想要系统行为的用户。**需要你确认。**
2. **Screen Recording** —— 缩略图类功能（Dock 预览、Cmd-Tab Plus、窗口缩略图）必须拿到这个权限。这是产品承诺层面的变更，只能挂在独立开关上。**需要你确认是否进范围。**
3. **Cmd-Tab Plus（接管系统切换器）** —— Wins 这么做，可行，但它是全清单里唯一一个"插进系统级手势"的功能，风险与收益不成比例。建议放在最后一个里程碑独立评估。**需要你确认是否进范围。**

**已知工程风险**：

- `CGEventTap` 监听 `leftMouseDragged` 是全局高频事件，必须做节流 + 快速 reject（Wins 有 `mouseMoveDetectionThrottle`、`Debouncer`、`Throttler`）。我们不达标会直接拖慢整机手感。
- 自绘标题栏应用（Electron）的 AX 行为不一致——`docs/window-titlebar-gesture-research.md` 已有实测结论，M2 要复用那些数据。
- 与 Stage Manager、系统自带拖拽分屏、第三方窗口管理器（Magnet/Rectangle 同时开）三者的冲突需要有明确的检测与提示。
- 性能目标按 Wins 的公开口径定：内存 < 40 MB、CPU < 10%、空闲 ~0.1%；用 `PerformanceLogService` 量化并写进验收。

---

## 十、复现命令

```bash
# 安装包
hdiutil attach ~/Downloads/Wins-latest.dmg -nobrowse -readonly

# 类与反射元数据
lipo -thin arm64 "/Applications/Wins.app/Contents/MacOS/Wins" -output /tmp/Wins_arm64
strings -a /tmp/Wins_arm64 | grep -oE '_TtC4Wins[0-9A-Za-z_]+' | sort -u      # 197 个类
otool -l /tmp/Wins_arm64 | grep -A4 __swift5_reflstr                          # offset 2274048, size 0x5d6b
dd if=/tmp/Wins_arm64 of=/tmp/reflstr.bin bs=1 skip=2274048 count=$((0x5d6b))
strings -a -n 3 /tmp/reflstr.bin                                              # 全部 Swift 属性名
otool -oV /tmp/Wins_arm64 > /tmp/wins_objc.txt                                # ivar + 方法签名

# 权限与功能面
codesign -d --entitlements - "/Applications/Wins.app"
ls "/Applications/Wins.app/Contents/Resources/Wins.prefPane/Contents/Resources/"*.mp4
```

功能演示视频（20 段，可直接看动画节奏）：
`/Applications/Wins.app/Contents/Resources/Wins.prefPane/Contents/Resources/{snapIsland,edgeSnap,aeroShake,center,nextDisplay,prevDisplay,dockPreviewView,commandTabPlus,hiddenOtherWindows,hiddenAllWindow,dockLock,flickDock,missionControlPro*}_*.mp4`

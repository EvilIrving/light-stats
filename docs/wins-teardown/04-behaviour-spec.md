# 04 · 行为规格

这一份是"照着实现"用的。所有字段名都来自 `03-type-map.md` 的实测 ivar；标 **[B]** 的是从 ivar 组合推出的行为。

---

## 一、拖动流程的完整阶段（`WindowDragPerfStage`，41 个枚举 case）[A]

Wins 为了给拖动做性能统计，把整个拖动到落位的管线**逐个阶段枚举了出来**。这等于他们把自己实现的**全部步骤**写成了清单。按顺序：

```swift
enum WindowDragPerfStage {
    // 鼠标事件进入
    case snappingFilter            // 是否是我们关心的事件
    case snappingMouseDown         // 记下 mouseDownLocation
    case snappingMouseUp
    // 找出被拖的窗口
    case dragWindowHitTestAX       // AX 命中测试
    case dragWindowIdentifier      // AX 元素 → CGWindowID
    case dragWindowRectAX          // 从 AX 读 frame
    case dragWindowRectAXFallback  // AX 读不到时的退路
    case dragWindowRectWindowServer    // WindowServer 兜底
    case dragWindowRectWindowListFallback
    case dragSizeSettableAX        // 这个窗口能不能改大小
    // 各类附加判定
    case dragFlickDockPrepare
    case dragFlickDockRelease
    case dragSnapAreaDetection     // 落在哪个吸附区
    case dragStageManager          // 台前调度避让
    case dragExclusionCheck        // 排除 App
    case dragCursorNudge           // 鼠标位置微调
    case dragShake                 // 摇动检测
    case dragEdgeUpdate            // 边缘命中更新
    case dragIslandUpdate          // 悬浮岛更新
    case dragUnsnapRestore         // 取消吸附后还原
    // Dock 预览
    case dockPreviewForward
    case dockPreviewHandle
    case dockWindowAXObserver
    case dockWindowMainQueueDelay
    case dockWindowMainUpdate
    // 悬浮岛
    case islandShow
    case islandHide
    case islandLayoutReload
    case islandLayoutJSON
    case islandLayoutSanitize
    case islandInteractionUpdate
    case islandAnimationFrame      // 每一帧
    // 预览框
    case footprintTargetRect
    case footprintShow
    case footprintClose
    // 其它
    case screenDetection
    case missionControlHandle
    case missionControlSnapshot
    case missionControlProbe
    case missionControlDockScan
    case missionControlWindowManagerScan
    case windowEnumeration
    case screenshot
}
```

**注意 `dragWindowRect` 有 4 条路径**（AX → AX fallback → WindowServer → WindowList）。这不是过度设计，而是 macOS 上取窗口 frame 的真实难度：Electron、Java、部分游戏窗口在不同条件下会分别失败。我们现有的 `WindowGestureTargeting` 只走了一条路。

`dragSizeSettableAX` 说明**"能不能改大小"只查一次并缓存**（`SnappingManager.trackedWindowSizeSettable: Bool?`）——不是每帧都查。

## 二、拖动状态机（`SnappingManager`，21 个 ivar）[A]

```
依赖注入：paddleHelper, dockWindowPreviewer, clickDockShowAndMinimumController,
          snapAreaDetector, cursorNudger, footprintPresenter,
          snappingIslandCoordinator, unsnapRestorer, eventMonitor

当前被拖的窗口：
  windowElement              AXUIElement
  windowId: Int32?           CGWindowID
  windowIdAttempt: Int32     已经试了几次
  lastWindowIdAttempt: Double?   上次尝试的时间戳
  windowMoving: Bool
  isResizing: Bool
  initialWindowRect          CGRect
  trackedWindowSizeSettable: Bool?        缓存
  trackedWindowExclusionResult: Bool?     缓存
  currentSnapArea
  globleMouseLoc             NSPoint   ← 注意原始拼写
  mouseDownLocation          NSPoint
```

**[B] 推出的事实：**
1. 他们**跟踪单个被拖窗口**，不是每个窗口一份状态。
2. **`windowId` 是惰性解析并带重试**（`windowIdAttempt` + `lastWindowIdAttempt`）。原因是：mouseDown 那一刻窗口可能还没开始移动，AX 里拿不到稳定的标识。**这是我们必须预先知道的一个坑。**
3. **`windowMoving` 与 `isResizing` 分开**——拖边角改变尺寸时不当作移动处理。
4. `initialWindowRect` 只在拖动开始时记一次，用来算吸附和还原。
5. 排除判定和 size-settable 判定都缓存成 `Bool?`（`nil` = 没查过）。**拖动过程中不要反复查 AX**，这是性能关键。

## 三、吸附区判定（`SnapAreaDetector` + `SpringArea`）[A]

```
SnapAreaDetector:
  marginTop, marginBottom, marginLeft, marginRight
  ignoredSnapAreas
  snapOptionToAction

SnapArea (struct):
  screen: NSScreen
  action
  source: SnapAreaTriggerSource      // .Snap | .FloatingWindow
  executionSource
  customRect

SnapAreaOption            // 可以关掉的具体区域
SnapAreaTriggerSource: Snap / FloatingWindow   ← "悬浮分屏岛"在代码里就叫 FloatingWindow
SnapArea? + 外部标注为 cornerSnapAreaSize（角落吸附区尺寸）
```

**[B] 关键设计**：`margin` 同时参与**触发区判定**和**落位几何**。所以预览框和最终落位永远一致——这是他们不会出现"预览在这里、窗口跑到别处"的原因。

`sapAreaTriggerSource` 只有两个值，说明**边缘吸附和悬浮岛共用同一套 area/target 抽象**，只是触发源不同。我们要抄这个结构：不要给岛单独做一套。

## 四、悬浮分屏岛（`SnappingIsland*` 全家族）[A]

### 状态与过渡

```
SnappingIslandState:    collapsed | open
SnappingIslandTransition: show | expand | collapse | hide | resize
SnappingIslandMotion:   response: Double, dampingFraction, duration: Double,
                        timingFunction: CAMediaTimingFunction
```

**注意**：`SnappingIslandTransition` 是**过渡类型**（5 个 case），`SnappingIslandMotion` 是**参数结构体**（弹簧或曲线）。名字容易看反。

- `show` 首次出现 → `expand` 展开 → 离开时 `collapse` 缩成条 → 放弃 `hide`
- `resize` 是原地改尺寸（换屏幕、换布局），**不重放 show**

### 展开过程的外观插值

```
SnappingIslandShape:           topCornerRadius, bottomCornerRadius
SnappingIslandSolidBackground: topSeamGuardHeight, topCornerRadius,
                               bottomCornerRadius, showsShadow: Bool,
                               shadowProgress
```

**[B]**：`_visualOpenProgress`（0→1）同时驱动：
- `topCornerRadius` / `bottomCornerRadius`（上下圆角分开）
- `shadowProgress`（阴影不是开关，是跟着进度长出来）
- `topSeamGuardHeight`（与菜单栏之间的那道缝）

**上下圆角分开 + 阴影渐显 + 顶部留缝**，这三条就是"看起来贵"的全部来源。

### 窗口本体动画器（`SnappingIslandWindowAnimator`）[A]

```
window: NSWindow?  (weak)
startFrame, targetFrame: CGRect
startAlpha, targetAlpha: Double
topAnchorY: Double                   // 上边缘锚点，动画期间不变
startAlpha, targetAlpha: Double
motion: SnappingIslandTransition
onFrameUpdate, completion: 闭包
timer: Timer?, startTime: Double, didFinish: Bool
```

**[B] 这是一个 Timer 驱动的逐帧插值器**：每帧算进度 → 插值 frame 与 alpha → `onFrameUpdate` 写回窗口 → 结束调 `completion`。

**为什么不用 `window.animator()` / `NSAnimationContext`**：那套的中间帧拿不出来，而岛需要在动画途中同时改圆角、阴影、内容，并且要能被下一次输入打断。**这是本次拆解里最值得照抄的一条架构决策。**

`topAnchorY` 让岛看起来"从顶部菜单栏下面长出来"，而不是从中心缩放。

### 容器与交互

```
SnappingIslandWindow        : NSPanel
    isEditorInteractive: Bool          // 编辑布局时鼠标才可点
    canBecomeKeyWindow  = false
    canBecomeMainWindow = false
    overrides constrainFrameRect(_:to:)   ← 否则面板会被 AppKit 压在菜单栏下方
       （4 个方法里那个签名 `{CGRect}56@0:8{CGRect}16@48` 就是它）

SnappingIslandController:
    window, viewModel, screen, hideAnimationGeneration: Int,
    localEditingEventMonitor, globalEditingEventMonitor, editingFocusObserver,
    gridSelectorController, windowAnimator, activeTransition,
    $__lazy_storage_$_editorActions

SnappingIslandInteractionCoordinator:
    controller, activationDetector, lastActiveScreen: NSScreen?

SnappingIslandActivationDetector:
    topOverflowTolerance, horizontalTolerance,
    collapsedPreviewTopRatio, centerActivationWidthRatio
```

`hideAnimationGeneration: Int` 是**代际令牌**，防"隐藏过程中又被 show 叫回来"的竞态。
`lastActiveScreen` 说明岛**跟随最后活跃的显示器**，不是固定在主屏。

### 激活判定 [A/B]

四个参数就是一个完整的触发规格：
- `topOverflowTolerance`：拖动窗口的顶部超出屏幕上边缘多少才算"到顶"
- `horizontalTolerance`：水平方向的容差
- `centerActivationWidthRatio`：只有在屏幕中央这么宽的比例内才激活（避免贴角落也在顶部弹岛）
- `collapsedPreviewTopRatio`：折叠态露出屏幕高度的多少

### 布局数据模型 [A]

```swift
struct SnappingIslandLayoutDefinition { id: String; title: String; isBuiltIn: Bool; segments: [..] }
struct SnappingIslandLayoutSegment {
    id: String
    actionRawValue: Int
    legacySplitTypeRawValue: Int?
    rect: NormalizedRect
    customRect: CGRect?          // 用户拖出来的非网格矩形
}
struct NormalizedRect { x, y, width, height }     // 0–1，y 轴向上
struct GridCell { column: Int; row: Int }
struct SnappingIslandSavedPlacement { id, title, rect, createdAt: Double, isBuiltIn }
struct SnappingIslandLayoutDraft { title: String; selectedItems: [..] }   // 编辑中的草稿
struct SnappingIslandLayoutGroup { definition; frame; targets }
struct SnappingIslandTargetFrame {
    segment; action; legacySplitType; customRect; layoutID: String; groupFrame; frame
}
enum SnappingIslandEditorPanel { none; addLayout }
```

### 编辑器动作（`SnappingIslandEditorActions`，10 个闭包）[A]

```
deleteActiveLayout(String)
deleteActiveSegment(String, String)
moveActiveLayout(String, String)
resetLayouts()
openGridSelector()
deleteSavedPlacement(String)
moveSavedPlacement(String, String)
dropSavedPlacementOnActiveLayout(Bool, String, String, [String])
createActiveLayoutFromSavedPlacement(Bool, String)
finishEditing()
```

**这 10 个闭包就是布局编辑器的完整功能清单**——用户能做的全部事情就这 10 件。可以直接当我们的需求清单。

### 网格选择器

```
SnappingIslandGridSelectorController:
    window, localEventMonitor, globalEventMonitor, footprintPresenter, selectorSize
SnappingIslandGrid:      _viewModel, editorActions, editorCardSize, createDropTargetID
SnappingIslandGridSelectorView: 8 个字段
GridHoverReader / HoverTrackingView: 跟踪鼠标在哪个格子上
```
`SnappingIslandGridSelectorPanel : NSPanel`，只有一个 ivar `onCancel`。
`SnappingIslandGridSelectorController` 自己也带 `footprintPresenter` —— 选格子时也用同一个预览框。

### 编辑态的抖动

`__jiggle`（`SnappingIslandLayoutCardView` 上的 `@State`）——像 iOS 主屏编辑态那种左右微抖。属于锦上添花，但成本很低。

## 五、预览框（`FootprintPresenter` / `FootprintWindow`）[A]

```
FootprintPresenter: box
FootprintWindow : NSWindow
    closeWorkItem
    bgLayer: CALayer?
    status: Int
    showingType
```

**[B]**：预览框是一个 `NSWindow` + 一个 `CALayer` 背景；`status: Int` 是它的显示状态机；`closeWorkItem` 是延迟隐藏的取消句柄（`cancelPreviousPerformRequests` 式的做法）。

图片证据（`missionControlProStatus.mp4` 抽帧）：**2pt 左右的蓝色描边、内部几乎全透明**，直角圆角很小。

## 六、还原（`UnsnapRestorer` / `WindowHistory`）[A]

```
WindowHistory:
    restoreRects
    restoreCenterRects
    lastRectangleActions
    lastSystemActions      ← 区分"上一次是我们的动作"还是"系统/别的东西动的"
```

**[B] 这是他们 restore 正确的关键**：如果上次操作不是自己做的（用户手动拖动、系统分屏、其它工具），就不能用自己记的 rect 去还原。我们当前的 bug（原生路径不记原始 frame）正是缺了这一层。

`ExecutionParameters.updateRestoreRect: Bool` —— **是否更新还原点是一个参数**，说明有些动作不应该覆盖还原点（例如连续吸附）。

## 七、时序常数（实测到的）

从日志字符串中提取到的具体数值 [A]：

| 值 | 出处 | 推测含义 |
|----|------|---------|
| `delaySeconds=0.45` | `dockWindow.mainQueueDelay` 附近 | Dock 预览/AX 读取的延迟 |
| `thresholdMs=16.000` | WindowDragPerf | **一帧 16 ms** 的性能预算，拖动阶段的耗时判定 |
| `debounceInterval` / `interval` | `Debouncer` / `Throttler` | 通用节流（`Throttler { queue, interval, semaphore, workItem, lastExecuteTime }`） |
| `mouseMoveDetectionThrottle`、`mouseEventThrottle`、`scrollEventThrottle` | CommandTabPlus | 三套独立节流 |
| `appTitleCacheTTL`、`dockAppCacheTTL`、`cacheValidDuration` | CommandTabPlus / Dock | 缓存有效期 |
| `successfulMoveCooldown`、`automaticRetryDelay`、`displayConfigurationRetryDelay`、`healthInterval`、`automaticPointerIdleInterval` | DockDisplayLockController | 重试与冷却 |
| `dragEndSuppressionInterval`、`suppressXMarkUntil` | MissionControl | 拖动结束后抑制 X 按钮的时长 |
| `requestTimeout`、`observationDelays` | MissionControlCloseCoordinator | 关窗结果验证的超时 |

**其余数值常量（如 `topOverflowTolerance` 具体是几）无法从二进制读出**——ivar 只有名字。这是本次拆解的边界，实现时按手感调。

## 八、并发与 AX 命令

日志里两条关键字符串 [A]：

```
queue=accessibilityCommandsQueue note=asyncWithCap-waits-synchronously-before-return
queue=global.userInteractive
```

**[B] 他们把 AX 调用串行化到一条专用队列上**，并且注释说明"有并发上限，并且在返回前会同步等待"。原因：AX 调用对同一个 App 是串行的，并发调用会互相阻塞甚至超时。这解释了为什么他们的 `SystemMonitor` 风格的定时采集不会和拖动抢 AX。

`MissionControlCloseCoordinator` 里还有一个完整的**异步请求/验证框架**：

```
requestID, sessionID, epoch, generation, activeRequest, destructiveLease,
observationCancellation, requestTimeoutWorkItem, resolutionPending,
consecutiveCompleteAbsences, rolloverCandidateWindowID, ...
加上一组 outcome：accepted / rejectedAlreadyClosing / rolledOver / closed /
unconfirmed / aborted / sessionEnded
```

**这是一个可以直接抄的"动作 + 校验"模板**：发起 → 观察 → 验证 → 分门别类地给出结果，而不是乐观地假设成功。

## 九、OS 版本分支

日志字符串里出现成对的模式 [A]：

```
mode=macos27 result=ordered-front windowNumber=
mode=macos27 result=no-op-same-visible windowNumber=
mode=windowserver-fallback result=
mode=legacy windowNumber=
reason=notInCGS
```

**[B]**：抬升窗口（`ordered-front`）在不同 macOS 版本上行为不同，他们按版本分支，并且有"同一个窗口已经在最前 → no-op"的判断，以及 WindowServer 兜底和"不在 CGS 里"的排除。

**对我们的意义**：不要假设"把窗口置前"是一个稳定 API。我们的目标系统是 macOS 14+，落在 macos26/27 这一段，需要自己验证。

## 十、性能自监测（`WindowDragPerf*`）[A]

```
WindowDragPerfStage           41 个阶段（见第一节）
WindowDragPerfEventToken      6 个字段
WindowDragPerfSessionToken    1
WindowDragPerfDiagnostics
TimingStats { count, totalNanoseconds, maximumNanoseconds }
SummarySnapshot { label, sessionID, durationNanoseconds, eventCounts,
                  eventTimings, stageTimings, counters, slowMainEvents }
```

对照我们的 `DiagnosticLogService`（always-on 故障日志）+ `PerformanceLogService`（opt-in 性能记录）——**Wins 把这两件事合并成了一个"窗口拖动会话"**，且有 `windowDragPerfVerboseLog` 开关（实测 `0`）。

值得抄的点：**他们对待性能诊断的态度是把每个阶段都插桩并统计 max，不是只看平均值**（`TimingStats.maximumNanoseconds`）。拖动卡顿是瞬时事件，平均值会掩盖它。

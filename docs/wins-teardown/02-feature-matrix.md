# 02 · 功能矩阵与设置键

默认值全部来自 **这台机器上 Wins 真实写出的** `~/Library/Preferences/cools.wins.main.plist`（47 个键）[A]。
所有设置项都通过类型化包装器读写：`BoolDefault` / `IntDefault` / `FloatDefault` / `StringDefault` / `OptionalBoolDefault` / `IntOptionDefault` / `SubsequentExecutionDefault`（`Wins.Defaults` + `Wins.BoolDefault` 等类）[A]。

界面标签来自 `Wins.prefPane/Contents/Resources/zh-Hans.lproj/Localizable.strings`（42 个键）与用户截图 [A]。

## 一、设置页第一屏（截图实测）

| 界面标签 | 设置键 | 实测默认 | 实现要点（来自类型表） |
|---------|--------|:-------:|---------------------|
| 开启 Wins，将会在后台运行 | （总开关） | 开 | 关掉后不装任何事件监听 |
| **屏幕边缘分屏** | `edgeSnap` | **开** | `SnapAreaDetector`（marginTop/Bottom/Left/Right + ignoredSnapAreas） |
| **悬浮分屏岛** `新功能` | （随岛功能） | 开 | `SnappingIslandController` + `SnappingIslandInteractionCoordinator` |
| **摇动窗口** | `enableShakeHiddenWindows` | **开** | `DragShakeChecker`（无 ivar，纯函数） |
| **Dock 窗口预览** | `enableDockPreview` | **开** | `DockPreviewerWC` + `DockWindowPreviewController` + 缩略图缓存 |
| **调度中心 Pro** | `missionControlProStatus` | **开** | `MissionControlPro`（41 个 ivar） |
| **Dock 窗口反转** | `enableFlickDock` | **关** | `FlickDockController`（11 ivar） |
| **Cmd-Tab Plus** | `commandTabPlus` | **开** | `CommandTabPlus`（33 ivar） |
| 调度中心 Pro › 关闭窗口 | `missionControlProClosesWindowStatus` | 关 | `MissionControlCloseCoordinator` |
| 调度中心 Pro › 退出程序 | `missionControlProQuitAppStatus` | 关 | 同上 |

## 二、分屏行为细项

| 界面标签 | 设置键 | 实测默认 | 说明 |
|---------|--------|:-------:|------|
| 分屏窗口间距 | `snapMarginEnable` | **关**（opt-in） | 开启后 marginTop/Bottom/Left/Right 生效，**并且同时内缩触发区**；`applyGapsToMaximize` / `applyGapsToMaximizeHeight` 说明最大化也吃间距 |
| 显示分屏预览框 | `showSplitWindow` | **开** | 就是 `FootprintWindow` 那个蓝框；关掉则拖动无预览 |
| 窗口居中 | `centerStatus` | 开 | `CenterCalculation` + `CenteringFixedSizedWindowMover`（小窗口不拉伸，改居中） |
| 移动到下个显示器 | `nextDisplayStatus` | 开 | `NextPrevDisplayCalculation` / `moveToAdjacentDisplay` |
| 移动到上个显示器 | `prevDisplayStatus` | 开 | 同上 |
| 分屏岛配色 | `floatingColor` | `0`（灰） | 资产 `FloatingGreyColor` / `FloatingBlueColor` / `FloatingActiveColor` |
| 预留台前调度空间 | `respectStageManager` | **开** | 拖动流程里有独立的 `drag.stageManager` 阶段 |
| 排除 App | `exclusionApps` | `[]` | JSON 数组，模型是 `ExclusionAppModel { id:Int, appName, appStatus:Bool, appPath }` |

## 三、窗口可见性 / 隐藏

| 界面标签 | 设置键 | 实测默认 | 说明 |
|---------|--------|:-------:|------|
| 隐藏所有窗口 | `hiddenAllWindowStatus` | 开 | `HiddenAllRestoreSnapshot` + `HiddenAllRestoreSnapshotItem`（记 space / 轴向序 / cgWindowId / pid 以便还原） |
| 隐藏其他窗口 | `hiddenOtherWindowsStatus` | 开 | 摇动窗口触发 |
| 悬浮窗口（`Wins 会排除如下 App…`） | 随 `exclusionApps` | — | |
| 退出软件 | — | — | |

## 四、Dock 相关

| 界面标签 | 设置键 | 实测默认 | 说明 |
|---------|--------|:-------:|------|
| Dock 锁定屏幕 | `dockDisplayLock.enabled` + `dockDisplayLock.targetUUID(s)` | 未启用 | `DockDisplayLockController`（25 ivar）；`Prerequisite` = `{dockAtBottom, dockAutoHideDisabled, separateSpacesEnabled}`；`MoveError` 有 7 种失败：`prerequisitesNotMet / verificationFailed / displayDisconnected / accessibilityPermissionRequired / noReachableDockEdge / eventSourceUnavailable / dockProcessChanged` |
| （无标签，行为开关） | `moveDockToThisDisplayStatus` | 开 | 把 Dock 移到鼠标所在显示器 |
| （无标签） | `dockDisplayLock.noRestartMigrationCompleted` | `1` | 迁移标记位 |

## 五、其它

| 界面标签 | 设置键 | 实测默认 |
|---------|--------|:-------:|
| 开机启动 | `launchOnLogin` | `1` |
| 检查新版本 | Sparkle `SU*` | 自动 |
| 授权 | `purchaseActived` / `purchaseRemainDays` | `0` / `1`（试用中） |
| 解绑设备 | Paddle `Paddle-Wins-781505-SD` | — |
| 各功能详细日志 | `*VerboseLog`（edgeSnap 无、dockLock/dockPreview/flickDock/hiddenAllWindow/hiddenOtherWindows/missionControlPro/commandTabPlus/windowDragPerf） | 全 `0` |

**`*VerboseLog` 是一组很好的设计参考**：每个子系统一个开关，默认关，出问题时让用户单独打开而不淹没日志。我们的 `DiagnosticLogService` 可以直接沿用这个模式。

## 六、内置布局（实测的完整内容）

`snappingIslandLayouts` 里**只有 4 个内置布局**。这修正了从类名（62 个 `*Calculation`）得出的"他们有几十种布局"的猜测——**计算类 ≠ 用户可见布局**。

```json
[{"id":"built-in-halves","title":"Halves","isBuiltIn":true,"segments":[
   {"id":"left-half","actionRawValue":0,"legacySplitTypeRawValue":0,"rect":{"x":0,"y":0,"width":0.5,"height":1}},
   {"id":"right-half","actionRawValue":1,"legacySplitTypeRawValue":1,"rect":{"x":0.5,"y":0,"width":0.5,"height":1}}]},

 {"id":"built-in-thirds","title":"Thirds","isBuiltIn":true,"segments":[
   {"id":"first-two-thirds","actionRawValue":21,"legacySplitTypeRawValue":2,"rect":{"x":0,"y":0,"width":0.66,"height":1}},
   {"id":"last-third","actionRawValue":24,"legacySplitTypeRawValue":3,"rect":{"x":0.66,"y":0,"width":0.34,"height":1}}]},

 {"id":"built-in-right-stack","title":"Right Stack","isBuiltIn":true,"segments":[
   {"id":"left-half","actionRawValue":0,...},
   {"id":"top-right","actionRawValue":16,"legacySplitTypeRawValue":5,"rect":{"x":0.5,"y":0.5,"width":0.5,"height":0.5}},
   {"id":"bottom-right","actionRawValue":14,"legacySplitTypeRawValue":6,"rect":{"x":0.5,"y":0,"width":0.5,"height":0.5}}]},

 {"id":"built-in-quadrants","title":"Quadrants","isBuiltIn":true,"segments":[
   {"id":"top-left","actionRawValue":15,"rect":{"x":0,"y":0.5,"width":0.5,"height":0.5}},
   {"id":"bottom-left","actionRawValue":13,"rect":{"x":0,"y":0,"width":0.5,"height":0.5}},
   {"id":"top-right","actionRawValue":16,"rect":{"x":0.5,"y":0.5,"width":0.5,"height":0.5}},
   {"id":"bottom-right","actionRawValue":14,"rect":{"x":0.5,"y":0,"width":0.5,"height":0.5}}]}]
```

三个必须注意的细节：

1. **`rect` 是归一化的，但 y 轴向上（Cocoa 语义）**。判定依据：`top-left` 的 `y = 0.5`，`bottom-left` 的 `y = 0`。写我们的实现时如果混用 flipped 坐标，会整体上下镜像——这是最容易踩的坑。
2. **内置的 "Thirds" 不是三等分，而是 2/3 + 1/3**（`0.66` / `0.34`）。三等分只存在于快捷动作里。
3. **`actionRawValue` 与 `legacySplitTypeRawValue` 是两套独立编号**。实测映射：

| `actionRawValue` | 语义 |
|--:|------|
| 0 / 1 | 左半 / 右半 |
| 13 / 14 / 15 / 16 | 左下 / 右下 / 左上 / 右上 |
| 21 / 24 | 前 2/3 / 后 1/3 |

`legacySplitTypeRawValue` 0–10 是旧版枚举（0=左半,1=右半,2=前2/3,3=后1/3,4=左半,5=右上,6=右下,7=左上,8=左下,9=右上,10=右下），用于兼容旧配置的读入。

`snappingIslandSavedPlacements = null` —— 用户自定义布局存这里（`SnappingIslandSavedPlacement { id, title, rect, createdAt, isBuiltIn }`）。

## 七、我们 vs Wins（现状对照）

| 能力 | Wins | Light Stats 现状 | 差距性质 |
|------|:----:|----------------|---------|
| 边缘 / 角 / 三分 / 跨屏 / 最大化 / 还原 / 居中 / 最小化 | 有 | **有**（19 个 action） | 持平 |
| 拖动到边缘触发 | 有（`SnappingManager` 监听拖动） | **无**（只有标题栏滚动手势） | 缺失 |
| 拖动预览（footprint） | 有，可关 | 有，但只有 alpha 淡入 | 质感 |
| 悬浮分屏岛 | 有 | 无 | 缺失 |
| 自定义布局 / 网格选择器 / 保存位置 | 有 | 无 | 缺失 |
| 间距（margin） | 有，opt-in | 无 | 缺失 |
| 排除 App | 有 | 无 | 缺失 |
| 摇动隐藏其他窗口 | 有 | 无 | 缺失 |
| 隐藏所有 / 隐藏其他 | 有 | 无 | 缺失 |
| 台前调度避让 | 有 | 无 | 缺失 |
| 快捷键可录制 | 有 | 无（6 个硬编码） | 缺失 |
| Dock 窗口预览（缩略图） | 有（需屏幕录制） | 无 | 需新权限 |
| Cmd-Tab Plus | 有（需屏幕录制） | 无 | 需新权限 |
| 调度中心 Pro（关窗/退 App 快捷键） | 有 | 无 | 缺失 |
| Dock 锁定屏幕 / Dock 反转 / 移动 Dock | 有 | 无 | 与产品定位不符 |
| 授权 / 更新 | Paddle + Sparkle | 自研 LicenseCodec + UpdateService | **不动** |

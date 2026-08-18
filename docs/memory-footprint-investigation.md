# Light Stats 内存占用调查与优化笔记

> 状态：调查草案，尚未实施本文中的优化。
>
> 目标：在不牺牲菜单栏监控能力和弹窗体验的前提下，评估并降低 Light Stats 的内存、CPU 与后台能耗。
>
> 当前观察：Activity Monitor 中约 110 MB。该数字来自人工观察，尚未在统一的 Release 测试条件下建立基线，因此本文中的收益均为量级估算，不是已验证结论。

## 目标

期望指标：

```text
弹窗可见时高峰：< 80 MB
弹窗关闭、不可见并稳定后：< 40 MB
```

这两个目标应分别验收：

- **可见态**包含完整 SwiftUI 面板、背景 Scene、图表、进程榜和可能的动画。
- **隐藏态**只应保留菜单栏状态项、必要的系统指标采样，以及用户主动开启的额外服务。
- “高峰”与“稳定值”不能混用。关闭窗口后建议等待 20–30 秒，再记录稳定值。
- Debug 构建的内存与 CPU 不作为发布指标；正式验收必须使用 Release 构建。

## 当前生命周期

### 启动阶段

`Light Stats/AppDelegate.swift` 的 `applicationDidFinishLaunching(_:)` 当前依次执行：

```text
setupStatusItem()
setupPanel()
startMonitoring()
```

`setupPanel()` 会在应用启动时立即创建并长期持有：

- `NSPanel`
- `HitRetainingHostingView`
- 完整 `PopoverContentView`
- 当前主题的 `BackgroundHost` / `BackgroundSceneRouter`
- SwiftUI 环境对象、View 状态及相关 AppKit/Core Animation 资源

Panel 同时设置：

```swift
panel.isReleasedWhenClosed = false
```

### 弹窗关闭阶段

`dismissPanel(reason:)` 当前主要执行：

```swift
panel?.orderOut(nil)
monitor.setPopoverVisible(false)
appMemoryManager.stopMonitoring()
```

这会停止 Cleanup 采样并隐藏窗口，但不会释放 Panel、HostingView 或完整 SwiftUI 视图树。

因此当前语义更接近：

```text
关闭弹窗 = 不可见，但完整 UI 仍常驻
```

而不是：

```text
关闭弹窗 = 释放重型 UI，只保留菜单栏核心
```

这是隐藏态内存最值得优先验证的方向。

## 三项局部优化的收益估算

以下估算来自现有代码路径和资源量级分析，尚未通过 Instruments 或 Release A/B 测量验证。各项可能影响同一批缓存和临时分配，不能简单相加。

| 优化项 | 稳态内存估算 | 瞬时峰值估算 | 主要收益 |
|---|---:|---:|---|
| 状态栏风扇不再逐帧重建整张图片 | 降低约 0–3 MB | 降低约 1–5 MB | CPU、分配频率、后台能耗 |
| 面板不可见时仅停止动画 | 降低约 0–5 MB | 降低约 2–10 MB | CPU/GPU、唤醒次数、避免继续抬高内存水位 |
| Cleanup 仅停止扫描 | 降低约 0–3 MB | 降低约 2–10 MB | `ps`、进程解析、系统调用与临时分配 |
| Cleanup 停止并清空结果/图标 | 降低约 2–10 MB | 同时消除后续扫描峰值 | 释放进程数组、应用图标和详细快照 |
| 释放完整 Panel/HostingView | 降低约 15–40+ MB | 降低约 20–50 MB | 最可能显著改善隐藏态 |

### 结论

前三项值得做，但其主要价值偏向 CPU、能耗和分配抖动。仅靠它们，约 110 MB 的隐藏态大概率只会下降到约 95–108 MB，不能合理预期直接达到 40 MB。

若要产生几十 MB 的台阶式下降，核心实验应是：

```text
隐藏 Panel
    对比
销毁 Panel + HostingView + 背景 Scene
```

## 1. 状态栏风扇动画

### 当前行为

`Light Stats/Views/StatusBar/StatusBarView.swift` 使用 `CADisplayLink` 驱动风扇：

1. 每帧进入 `stepFan(_:)`。
2. 根据 RPM 和帧间隔更新 `fanAngle`。
3. 调用 `renderAndApply()`。
4. `renderImage()` 创建新的完整 template `NSImage`。
5. Logo、CPU、GPU、内存、磁盘、网络、电池等静态内容也被重绘。
6. 新图片重新赋给 `NSStatusBarButton.image`。

只有约 14pt 的风扇在变化，但当前可能以每秒 60 或 120 次重建整条状态栏图片。

### 资源量级

假设状态栏图片宽约 220pt、高 22pt，在 Retina 2x 下，单张 RGBA 原始像素约：

```text
220 × 22 × 2² × 4 bytes ≈ 77 KB
```

若以 60 FPS 更新，理论像素数据周转约：

```text
77 KB × 60 ≈ 4.6 MB/s
```

这些分配不会全部永久累积，因此常驻内存收益通常只有 0–3 MB；但主线程绘制、对象分配和能耗收益可能明显得多。

### 已有独立方案

详细重构方案已记录在：

```text
docs/status-bar-fan-core-animation-validation.md
```

该方案保留静态状态栏图片，只把风扇放入独立 Core Animation 图层，RPM 变化只调整图层动画速度，取消逐帧 Swift 回调和整图重绘。

### 验证重点

风扇优化不应只看 Activity Monitor 内存，还应测量：

- 风扇关闭时的稳态 CPU；
- 风扇开启时的稳态 CPU；
- Time Profiler 中是否持续出现 `stepFan(_:)` / `renderImage()`；
- Allocations 中 `NSImage`、bitmap backing 和 autorelease 分配速率；
- 60 Hz 与 120 Hz 显示器差异；
- 面板关闭后是否仍持续回调。

## 2. 面板不可见时仅停止动画

`PopoverContentView` 的背景由以下路径创建：

```text
PopoverContentView
  -> BackgroundHost
  -> BackgroundSceneRouter
  -> 当前主题 Scene
```

Overview 中的风扇则由 `SpinningFanIcon` 使用 `TimelineView(.animation)` 驱动。SwiftUI 对不可见窗口通常会减少或停止部分显示更新，但不能把这种行为等同于释放视图树和渲染资源。

若关闭时只停止动画，仍会保留：

- `NSPanel`
- `NSHostingView`
- SwiftUI View graph
- Core Animation layer 树
- 窗口 backing surface
- 背景 Scene 状态
- 字体、符号、图像及渲染缓存

因此仅停止动画的合理预期是：

```text
稳态内存：下降约 0–5 MB
复杂动态背景的瞬时峰值：可能下降约 2–10 MB
CPU/GPU/能耗：通常比内存改善更明显
```

如果某个 Scene 自己持有大型纹理、位图或离屏 surface，停止时同时主动释放这些资源，收益才可能超出这个范围。

## 3. Cleanup 停止扫描

### 当前扫描路径

`AppMemoryManager` 默认每 5 秒采样一次。`ProcessService` 每轮会：

1. 启动 `/bin/ps -axo pid=,ppid=,rss=,comm=`；
2. 读取完整 stdout；
3. 把 `Data` 解码成 `String`；
4. 拆分所有行和字段；
5. 构建 `ProcessMemoryRow` 与 `TopProcessInfo` 数组；
6. 对最大的 80 个进程读取 physical footprint；
7. 查询进程路径、Bundle 和 responsibility；
8. 建立应用归属字典并聚合内存；
9. 发布应用列表和系统详细内存快照。

扫描期间会同时存在多份临时数据：

```text
ps Data
UTF-8 String
lines / components
ProcessMemoryRow 数组
TopProcessInfo 数组
Bundle/归属字典
AppGroup 聚合结果
```

### 当前停止行为

`AppMemoryManager.stopMonitoring()` 当前会停止 Timer、取消活跃 Task，并重置调度状态，但不会清空：

```swift
runningApps
allTopProcesses
detailedMemory
```

`runningApps` 中的 `AppGroup` 还持有 `NSImage` 应用图标；`ProcessService` 也继续持有 `bundleIdCache`。

因此：

- **停止扫描**主要消除下一轮临时分配和 CPU 工作；
- **停止并清空结果**才可能让隐藏态内存进一步回落；
- malloc/AppKit 可能保留已申请页面，清空对象后 Activity Monitor 数字也不保证立即下降。

### 收益判断

```text
仅停止扫描：稳态约 0–3 MB，单轮峰值约 2–10 MB
停止并清空快照/图标：额外约 2–10 MB
```

进程数量非常多时，单轮峰值可能更高；具体值需要 Allocations 和 Release A/B 测试确认。

## 4. 完整 Panel/HostingView 生命周期

### 为什么这是高优先级

透明的 360×780pt Panel 在 Retina 2x 下，单层原始 RGBA 像素量约：

```text
360 × 780 × 2² × 4 bytes ≈ 4.5 MB
```

实际 SwiftUI/AppKit 窗口还可能包含：

- 多个合成层；
- 阴影；
- 透明背景中间 surface；
- 背景 Scene 的渐变、Canvas 或材质；
- 文本与 SF Symbol 缓存；
- SwiftUI View graph 和 Observation/Combine 状态；
- 滚动内容与布局缓存。

所以完整 Panel 的实际增量可能远高于单个 backing surface。

### 候选生命周期

```text
应用启动
  -> 只创建状态栏核心

首次点击状态栏
  -> 创建 NSPanel + HostingView + PopoverContentView

关闭面板
  -> 停止 Cleanup 和 UI 专用采样
  -> 停止动画
  -> 移除 contentView / 释放 Panel
  -> 清空重型快照
```

也可考虑折中策略：

```text
关闭后先 orderOut
  -> 延迟 5–15 秒
  -> 若未重新打开，再释放 Panel
```

这样能兼顾快速重复打开和长期隐藏态内存。若 40 MB 是硬性目标，则应优先验证立即释放。

### 可能代价

- 下次打开需要重新创建 SwiftUI 层；
- 首次或再次打开可能增加几十毫秒延迟；
- 必须确认 tab 状态、主题、滚动位置是否应保留；
- 必须防止旧 Panel 的 observer、Task、动画或全局 monitor 残留；
- 需要验证设置窗口与主 Panel 是否共享或额外持有主题资源。

## 5. SystemMonitor 与趋势历史

`SystemMonitor` 当前维护 6 组、每组最多 60 个 `Double`：

```text
6 × 60 × 8 bytes ≈ 2.8 KB
```

因此趋势历史本身不是 110 MB 的主因。

但每轮采样都会从环形缓冲构造新的 `MetricTrends` 数组快照并发布，即使面板不可见也是如此。这会带来持续的小额数组复制、Combine 发布和潜在 View invalidation。

可验证的优化方向：

- Panel 不可见时继续保留私有环形缓冲，但不发布 UI 专用 `trends` 快照；
- Panel 打开时一次性发布当前快照；
- Panel 关闭时清空 `topCPUProcesses` 等只用于弹窗的数据；
- 不应为了几 KB 历史数据做复杂重构，重点是降低分配频率和无效 UI 通知。

## 6. 最近内存增长功能的性能边界

若未来加入“最近内存增长”与“按增长排序”，必须服从隐藏态目标：

- 只在 Cleanup 页面或 Panel 可见期间采集；
- 不为了过去一分钟趋势而让全进程扫描常驻后台；
- 关闭页面后停止扫描；
- 历史只保存应用身份、时间和字节数，不保存 `NSImage` 或完整进程对象；
- 关闭 Panel 后可以清空历史，再次进入显示“采集中”；
- 少量数值历史通常只有 KB 级，真正昂贵的是全进程扫描、Bundle 归属和图标。

## 统一测量方法

没有统一基线时，不应依据单次 Activity Monitor 读数决定实现。

### 构建条件

使用 Release 构建，不启动 Xcode 调试器：

```bash
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -configuration Release \
  -derivedDataPath build/DerivedData build
```

测试时固定：

- 同一台 Mac；
- 同一 macOS 版本；
- 同一显示器与刷新率；
- 同一主题；
- 同一组菜单栏指标；
- 同一 AI/网络/窗口工具开关；
- 相近的系统进程数量；
- 每次冷启动前确保旧进程已退出。

### 建议场景

每个场景重复至少 3 次，记录中位数：

| 编号 | 场景 | 等待时间 | 记录内容 |
|---|---|---:|---|
| A | 冷启动，从未打开 Panel | 30 秒 | 内存、CPU、线程数 |
| B | 打开 Overview | 10 秒 | 稳态与峰值 |
| C | 切换到 Cleanup，完成一次扫描 | 10 秒 | 扫描峰值、扫描后稳态 |
| D | 关闭 Panel，但保留 Panel 对象 | 30 秒 | 隐藏态稳态 |
| E | 关闭并释放 Panel/HostingView | 30 秒 | 与 D 的差值 |
| F | 状态栏风扇关闭 | 30 秒 | CPU/内存基线 |
| G | 状态栏风扇开启且 RPM > 0 | 30 秒 | 与 F 的差值 |
| H | 打开再关闭 Settings | 30 秒 | Settings 是否留下工作集 |

### 工具分工

- **Activity Monitor**：用户可见的粗略内存与 CPU 趋势。
- **Xcode Memory Graph**：检查 Panel、HostingView、Scene、ViewModel 是否仍被引用。
- **Instruments Allocations**：观察对象存活、分配速率和扫描期间临时峰值。
- **Instruments Leaks**：确认不存在实际泄漏。
- **Time Profiler**：确认状态栏风扇和隐藏态动画的 CPU 调用栈。
- **VM Tracker / `vmmap`**：区分 malloc、Core Animation、IOSurface、mapped file 等内存类别。

### 注意 Activity Monitor 的解释

Activity Monitor 的“内存”不是“当前所有 Swift 对象大小之和”。关闭对象后数字不立即下降并不必然表示泄漏，可能来自：

- malloc 保留空闲堆页供后续复用；
- AppKit/SwiftUI 字体、图像或布局缓存；
- Core Animation / IOSurface 回收时机；
- 动态库和 mapped file；
- 压缩内存与系统记账差异。

因此应同时比较：

```text
对象是否释放
分配是否持续增长
physical footprint 是否在稳定窗口回落
同一动作重复后是否阶梯式增长
```

## 推荐验证顺序

### P0：先建立真实基线

1. 用 Release 构建测 A–H 场景。
2. 记录默认主题和内存最高主题。
3. 用 Memory Graph 确认隐藏后 Panel/HostingView 仍存活。
4. 用 Allocations 确认 Cleanup 单轮峰值。
5. 用 Time Profiler 确认状态栏风扇热点。

### P1：验证 Panel 释放的收益

先做最小实验，不急于设计完整生命周期：

```text
关闭时释放 contentView 和 Panel
与仅 orderOut 做 A/B 对照
```

若收益达到 15 MB 以上，说明这是主路径；若收益很小，则转向 VM Tracker 检查真正占用类别。

### P2：处理常驻动画

依据现有 `docs/status-bar-fan-core-animation-validation.md` 验证独立 Core Animation 图层。

验收重点是 CPU 和分配频率，不以“必须降低几十 MB”为目标。

### P3：释放 Cleanup 结果

对比：

```text
stopMonitoring()
    与
stopMonitoring() + 清空快照/图标 + 有界 Bundle 缓存
```

确认清理是否影响再次打开速度，并确保正在进行的异步更新不会在关闭后重新发布旧数据。

### P4：停止隐藏态 UI 发布

仅在 Panel 可见时发布趋势、进程榜和其他纯 UI 快照，减少持续分配和无效 SwiftUI invalidation。

### P5：再决定是否增加内存增长排序

只有在隐藏态和可见态目标接近达成后，再加入“观察期间增长”。该功能必须继续使用可见态采集生命周期。

## 决策表

| 发现 | 判断 | 后续方向 |
|---|---|---|
| 释放 Panel 后下降 ≥15 MB | Panel/UI 是主因 | 实施惰性创建与关闭释放 |
| 释放 Panel 后下降 <5 MB | UI 对象不是主要 physical footprint | 使用 VM Tracker 定位 IOSurface、malloc、mapped file |
| 风扇开启 CPU 明显增加、内存变化小 | 与静态分析一致 | 优先做 Core Animation，按能耗验收 |
| Cleanup 扫描时峰值明显但关闭后回落 | 临时分配为主 | 优化解析与采样频率，不必过度清缓存 |
| Cleanup 关闭后对象仍大量存活 | 快照/图标保留 | 清空结果并限制缓存 |
| 每次开关 Panel 后内存阶梯式上升 | 疑似泄漏或系统缓存无界增长 | Memory Graph + Allocations 查持有链 |
| 内存稳定但 Activity Monitor 不回落 | 可能是 allocator/framework 工作集 | 看 VM 类别和重复操作是否继续增长 |

## 当前判断

1. **隐藏态 40 MB 是否可达，首先取决于完整 Panel/HostingView 是否释放。**
2. 状态栏风扇优化很重要，但主要改善 CPU、分配率和能耗，常驻内存预计只下降 0–3 MB。
3. 面板不可见时只停止动画，预计降低 0–5 MB；它不能代替销毁重型 UI。
4. Cleanup 只停止扫描，预计稳态降低 0–3 MB；停止后再清空快照和图标，可能额外降低 2–10 MB。
5. 打开态低于 80 MB 需要实测不同主题、窗口 surface 和 Cleanup 峰值后才能判断。
6. 最近内存增长功能应后置，并严格限定为可见期间采集，不能破坏隐藏态目标。

## 实验记录模板

```text
日期：
机器 / 芯片 / 内存：
macOS：
构建：Release commit/tag
显示器 / 刷新率：
主题：
菜单栏指标：
额外功能开关：

A 冷启动隐藏态：
B Overview 可见稳态 / 峰值：
C Cleanup 可见稳态 / 峰值：
D orderOut 后 30 秒：
E 释放 Panel 后 30 秒：
F 风扇关闭 CPU / 内存：
G 风扇开启 CPU / 内存：
H Settings 关闭后 30 秒：

Memory Graph 发现：
Allocations 发现：
Time Profiler 发现：
VM Tracker / vmmap 发现：
结论：
下一项最小实验：
```

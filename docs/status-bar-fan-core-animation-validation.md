# 状态栏风扇独立 Core Animation 图层重构方案

> 状态：方案已确认，待后续独立实施；本文档只固化需求、设计与验收边界，不包含代码改动。
>
> 目标：消除状态栏风扇动画导致的逐帧 Swift 回调和整张状态栏图片重绘，让动画成本主要由 Core Animation 合成线程承担。

## 结论

重构应当进行，但必须保持为一次边界清晰的性能优化，不改变状态栏产品行为。

现有 `StatusBarView` 继续负责 CPU、GPU、内存、磁盘、网络、电池、健康分数、Logo
等静态内容，并继续把这些内容渲染为 `NSStatusBarButton.image`。风扇在静态图片中只保留
一个透明的 22pt 槽位，实际图标改为状态栏按钮内部的独立 `CALayer`。

独立图层使用一条固定的、每秒一圈的 `CABasicAnimation` 旋转动画：

```text
keyPath = transform.rotation.z
fromValue = 0
toValue = -2π                 // 顺时针
duration = 1 second
repeatCount = infinity
timingFunction = linear
```

真实 RPM 不触发逐帧绘制，只转换为该图层的 Core Animation 时间速度：

```text
visualRevolutionsPerSecond = min(max(Double(rpm), 0) / 5000, 1) * 3
fanLayer.speed = visualRevolutionsPerSecond
```

因此 2500 RPM 对应 `1.5x`，即每秒 1.5 圈；5000 RPM 及以上封顶为每秒 3 圈；
`nil` 或 0 RPM 对应 `speed = 0`，动画停在当前角度而不是回到起点。

## 需求分析

### 当前实现

状态栏风扇位于 `Light Stats/Views/StatusBar/StatusBarView.swift`：

1. `CADisplayLink` 跟随显示器刷新频率回调 `stepFan(_:)`。
2. 每次回调根据 `dt` 和 RPM 累加 `fanAngle`。
3. `renderAndApply()` 重新创建完整的 template `NSImage`。
4. CPU、GPU、内存、网络、Logo、分隔线和风扇全部被重新绘制。
5. 新图片再次赋给 `NSStatusBarButton.image`。

这意味着只有 14pt 的风扇在旋转，却可能每秒 60 或 120 次进入 Swift 主线程、创建图片并
重绘整条状态栏。实际 Debug 采样曾观察到约 45%-57% CPU 和约 132 MB physical footprint，
主要栈落在 `StatusBarView.renderImage()` 与 `drawFan(in:)`。绝对数值受 Debug 构建、设备和
采样环境影响，不能直接当作 Release 指标，但热点归因足以说明当前动画路径不合理。

### 真正需要保留的行为

- 风扇仍显示在当前固定 22pt 槽位内，图标尺寸仍为 14pt。
- 风扇顺时针旋转，沿用当前 `5000 RPM -> 3 圈/秒` 的视觉映射。
- RPM 变化时角度连续，不回到 0 度，不闪烁。
- RPM 为 0 或未知时静止；重新获得 RPM 时从原位置继续。
- 关闭风扇显示后，图层隐藏并停止消耗动画资源。
- 状态栏整体仍然是一个按钮。点击风扇、风扇边缘或其他指标，都打开/关闭同一个主弹窗。
- 状态栏图标和文字继续适配浅色、深色及壁纸着色的菜单栏。
- VoiceOver 仍只识别一个状态栏控件，风扇不形成额外焦点。

### 本次不解决的问题

- 不修改 SMC 风扇转速采集、系统指标轮询频率或 Combine 数据流。
- 不改变弹窗中的 `SpinningFanIcon`；它由 `TimelineView` 驱动且会随弹窗隐藏停止，
  不属于这次状态栏常驻性能问题。
- 不调整状态栏字体、宽度、指标顺序、分隔间距或设置项。
- 不把视觉转速改成物理 `RPM / 60`。真实物理转速会快到无法辨认。
- 不引入私有 AppKit API、第三方依赖或新的全局定时器。

## 目标架构

```text
NSStatusBarButton
├── button.image
│   └── 静态 template image
│       ├── Logo / CPU / GPU / MEM / DISK / NET / BAT / HLT
│       └── 风扇位置：透明槽位
└── StatusBarView（透明宿主，hitTest -> nil）
    └── FanAnimationLayer
        ├── SF Symbol: fanblades.fill
        ├── 固定一圈的 CABasicAnimation
        └── RPM 只更新 CALayer.speed
```

`AppDelegate` 现有的按钮行为保持不变：

```swift
button.action = #selector(togglePanel)
button.target = self
```

`StatusBarView` 已经作为透明视图放在按钮层级内，并且 `hitTest(_:)` 返回 `nil`。新的风扇
图层只作为 `StatusBarView` 的子图层存在；`CALayer` 本身不参与 AppKit 事件命中，宿主视图
也明确不接收事件，因此点击会继续落到原 `NSStatusBarButton`，无需为风扇单独转发点击。

## 详细设计

### 1. 静态状态栏图片

保留 `StatusBarView.renderImage()` 和 template image 路径，因为该路径已经解决了 Retina
清晰度、字体排版以及菜单栏自动着色问题。

风扇开启时仍把一个 `DisplayItem(isFan: true)` 加入布局，维持原有宽度和相邻项目位置，
但 `drawContents(in:)` 不再调用 `drawFan(in:)`。它只跳过该槽位，使对应区域保持透明。

静态图片仍可在系统指标更新、设置开关变化或状态栏宽度变化时重建；必须消除的是动画帧
触发的重建。完成后 `renderAndApply()` 不得出现在任何 Core Animation 逐帧路径中。

### 2. 独立风扇图层

新增一个职责单一的 `FanAnimationLayer`，建议放在：

```text
Light Stats/Views/StatusBar/FanAnimationLayer.swift
```

它负责：

- 持有风扇 SF Symbol 的图层内容或 alpha mask。
- 创建并长期持有一条线性、无限循环、基础速度为每秒一圈的旋转动画。
- 接收 `setRPM(_:)`，把 RPM 映射为 `0...3` 的 Core Animation `speed`。
- 在速度变化时维护 Core Animation 的本地时间，保证相位连续。
- 接收槽位 frame、`contentsScale`、可见性和外观变化。
- 隐藏或销毁时移除动画，避免后台残留。

`StatusBarView` 继续拥有布局数据，并负责把风扇槽位转换成图层 frame。不要在
`FanAnimationLayer` 内复制 `DisplayItem` 宽度或顺序规则。

### 3. 变速、暂停和恢复

独立图层只播放一条基础动画，通过时间速度实现 RunCat 式变速。速度变化时不能简单地先
写 `speed` 再清空 `timeOffset`，否则可能发生角度跳变。

在父图层时间 `T` 下，先取得风扇图层当前本地时间 `L`，再设置：

```text
timeOffset = L
beginTime = T
speed = newSpeed
```

这样切换前后的动画本地时间相同：

```text
0 -> 1000 -> 3000 -> 5000 -> 3000 -> 1000 -> 0 -> nil
```

整个序列都应保持当前角度。`newSpeed == 0` 时本地时间冻结；重新设置正速度后从冻结位置
继续。这里不需要每次 RPM 更新都删除并重建动画，也不需要 `CADisplayLink`。

### 4. 图标着色

这是方案中唯一需要先做视觉原型确认的风险点。

`NSStatusBarButton.image` 会自动把 template image 着色为当前菜单栏前景色，包括壁纸造成的
深浅变化。普通 `CALayer.contents` 不会自动获得完全相同的 AppKit template tint。

实施时按以下优先级验证公开 API：

1. 使用 SF Symbol 的 alpha mask，由独立图层填充从按钮当前外观解析出的前景色。
2. 在 `NSStatusBarButton` 的 `effectiveAppearance` 下绘制 template symbol，并在外观变化时刷新。
3. 如果公开 API 仍无法与按钮 template tint 一致，再评估由同一 mask 同时驱动静态内容和
   风扇颜色；不得使用硬编码黑色或白色掩盖差异。

不默认引入 `NSVisualEffectView(material: .sidebar)`，因为它可能在菜单栏上形成可见材质块。
如果公开 API 无法做到视觉一致，本重构应停在原型阶段，而不是用颜色不一致换取性能数字。

### 5. 几何与显示器变化

风扇 frame 必须从 `displayItems` 的实际布局结果计算：累加风扇之前所有项目宽度和分隔间距，
得到 22pt 槽位，再将 14pt 图层居中。禁止另建一套基于项目开关的硬编码偏移。

以下情况需要重新同步 frame 和 `contentsScale`：

- 状态栏项目开关变化。
- 状态栏按钮宽度变化。
- 菜单栏在 1x/2x 显示器之间移动。
- 主显示器或 backing scale 变化。
- 睡眠后唤醒。

几何更新和 RPM 更新是事件驱动的，不引入轮询。

### 6. 生命周期

```text
风扇设置关闭
  -> 隐藏图层、移除动画、speed = 0

风扇开启 + RPM nil/0
  -> 显示静态图层、动画冻结

风扇开启 + RPM > 0
  -> 确保基础动画存在、更新 layer.speed

StatusBarView deinit
  -> removeAllAnimations()
```

显示器休眠期间不依赖墙钟累加角度；Core Animation 恢复后继续自己的本地时间。若系统恢复
造成异常时间跳跃，以“保持当前 presentation angle、重新锚定本地时间”为准。

## 文件落点

预计只涉及以下生产文件：

| 文件 | 变更 |
|---|---|
| `Views/StatusBar/StatusBarView.swift` | 删除风扇 `CADisplayLink`、`fanAngle` 和逐帧 `renderAndApply()`；保留透明槽位；管理独立图层的 frame、RPM 和外观 |
| `Views/StatusBar/FanAnimationLayer.swift` | 新增独立旋转图层及连续变速/暂停逻辑 |
| `AppDelegate.swift` | 原则上不改点击逻辑；仅在宿主附着或外观通知确有需要时做小范围接线 |

测试只覆盖可纯计算的速度映射、槽位几何和动画状态转换。Core Animation 的实际相位、菜单栏
着色和点击行为以运行时验证为准，不为此搭建通用 UI 测试脚手架。

## 实施阶段

### 阶段 A：建立可比基线

- 使用同一台 Mac、同一 Release 构建和同一组状态栏项目记录风扇关闭/开启时的 CPU。
- 用 Time Profiler 确认现有热点仍是 `renderImage()`、SF Symbol 绘制和 `stepFan(_:)`。
- 保存浅色、深色、壁纸着色菜单栏的现状截图，作为着色和几何基准。

### 阶段 B：只验证静态独立图层

- 保留现有动画代码暂不删除，只让独立图层显示一个静止风扇。
- 验证 template tint、14pt 尺寸、22pt 槽位、1x/2x 清晰度和所有项目组合。
- 该阶段着色不通过则停止，不进入动画迁移。

### 阶段 C：迁移动画

- 加入固定一圈的 `CABasicAnimation` 和 RPM -> `layer.speed` 映射。
- 验证正向变速、降速、0 RPM 暂停、恢复、隐藏和再次显示时相位连续。
- 删除 `CADisplayLink`、`fanAngle`、`lastFanTimestamp` 以及动画帧中的整图重绘。

### 阶段 D：交互与性能验收

- 点击风扇中心、边缘、相邻分隔线和其他指标，都必须触发原 `togglePanel`。
- VoiceOver 只出现一个状态栏控件。
- 睡眠/唤醒、切换显示器、切换风扇设置后没有残留动画、错位或模糊。
- 重复与阶段 A 相同的性能采样，确认主线程不再承担当帧绘制。

## 验收标准

以下条件全部满足后才能合并：

- 状态栏风扇不存在 `CADisplayLink` 或其他逐帧 Swift 回调。
- 动画运行时不会逐帧调用 `renderImage()`、`drawFan(in:)` 或重新赋值 `button.image`。
- Time Profiler 中动画稳态不再持续出现 Light Stats 自身的风扇逐帧调用栈。
- 同配置 Release 构建中，风扇开启相对关闭的稳态 CPU 中位数增量不超过 1 个百分点；
  若采样环境噪声超过该值，需要记录噪声并证明已不存在应用侧逐帧工作。
- 视觉速度保持 `5000 RPM -> 3 圈/秒`，高于 5000 RPM 不再加速。
- RPM 变速、暂停和恢复没有可见角度跳变。
- 风扇槽位尺寸、指标顺序、状态栏总宽度与当前版本一致。
- 浅色、深色和壁纸着色菜单栏下，风扇颜色与其他 template 内容肉眼不可区分。
- 点击风扇区域仍打开/关闭同一个主弹窗，不增加事件拦截层。
- 风扇关闭、RPM 为 0、应用退出后不存在活跃动画或持续资源增长。

## 风险与回退

| 风险 | 处理 |
|---|---|
| 独立图层颜色与 `button.image` 不一致 | 把静态着色原型作为前置闸门；不接受硬编码颜色 |
| 变速时角度跳变 | 变更 `speed` 时同时锚定 `timeOffset` 与 `beginTime` |
| 图层覆盖按钮点击 | 图层放在 `hitTest -> nil` 的透明宿主内，不创建独立控件 |
| 项目开关后风扇错位 | frame 只从现有 `displayItems` 布局计算 |
| Retina 或跨屏后模糊 | 根据宿主窗口 backing scale 更新 `contentsScale` |
| 优化后性能仍异常 | 用 Time Profiler 检查是否仍有静态图片频繁重建；不以降低动画帧率作为最终方案 |

若公开 API 无法让独立风扇图层匹配菜单栏 template tint，保留当前实现并记录阻塞原因。回退
必须是完整回退到现有渲染路径，不能留下双重风扇、透明空槽或点击区域变化。

# Background Scene 架构迁移执行方案（历史归档）

> **文档状态：已归档并被当前实现取代，不是可执行方案。**
> 原方案编写时间：2026-08-16 CST
> 当前状态核对日期：2026-08-18
> 适用仓库：`swift-light-stats`

本文件保留 2026-08-16 的迁移方案，仅用于设计历史、决策追溯和理解架构演进。
下方旧正文中的阶段、命令、输出路径、不变量、验收矩阵和“第一个动作”均不得作为
当前实施指令。需要验证现状时，应以当前源码、测试和仓库级文档为准。

## 当前状态（2026-08-18）

- 当前用户可见主题为 `glass / film / bar / noir`，界面名称依次为
  Default、Neon、Night Bar、Ink Night。
- `dataPaper` 仍存在但对用户隐藏。Bento 与 Ash Veil 已删除，不再是产品主题、布局
  或验收目标。
- 当前 Router / Scene 集合包括 `systemGlass`、`sunGold`、`bar`、`inkNight` 和
  `technicalPaper`。
- 所有当前主题使用统一的 instrument layout，不再保留 Bento 专属布局分支。
- `VisualThemeCaptureTests` 已覆盖当前四个用户可见主题。主题截图必须通过当前测试
  生成并采用测试实际报告的输出，不得依赖本文件旧正文列出的文件名、数量或路径。

## 以下为历史迁移方案（仅供设计追溯）

## 结论

用户提出的方向正确，应继续保留现有产品模型：

```text
AppTheme -> ThemeDefinition(ui + background + layout)
```

## 实施后扩展（2026-08-16）

原迁移范围中的四个主题与 raw value 保持不变；架构完成后新增第五个产品主题
`dataPaper`，固定组合为 `UITokens.dataPaper + BackgroundSceneID.technicalPaper +
ThemeLayout.instrument`。Technical Paper 是独立静态 Canvas Scene，不使用 Glass、
Grain、Veil、Blur、Flow 或 Light Field。

Sun Gold 与 Ink Night 进一步增加各自的强类型 Scene Configuration。Flow、Motion、
Grain、Veil 以及具名 Light Field Layer 的启用、blur、opacity、motion scale 均为
代码侧参数；现有用户设置只覆盖 grain 开关和 light flow。`ThemeLayout` 已与
`UITokens` 解耦并单独注入环境，成为业务 View 的唯一布局真相。

## 原迁移范围

用户只选择团队设计好的 `glass / bento / film / noir` 四个产品主题，不增加独立背景选择器，也不允许用户自由混搭 UI、布局和背景。

需要继续拆除的是第二层 Mesh 中心模型。当前 `BackgroundConfiguration`、`ThemeBackgroundView` 和设置页仍把所有背景假定为同一种管线：`kind -> mesh renderer -> shared motion -> veil -> grain`。目标应改为纯 `BackgroundSceneID` 加一个 `@ViewBuilder` Router，每个 Scene 独立决定使用 SwiftUI、AppKit、Canvas、Image 或 Metal，以及是否需要自己的时间线、合成组和效果。

本方案批准以下核心边界：

- `ThemeDefinition.background` 最终只保存 `BackgroundSceneID`。
- `BackgroundHost` 只负责容器职责：填满调用方尺寸、圆角裁切、窗口上下文转交、统一 `.allowsHitTesting(false)`。
- `BackgroundSceneRouter` 是唯一的 Scene 创建入口，使用 `@ViewBuilder switch`，不使用 `AnyView`。
- `SystemGlassScene`、`SunGoldScene`、`InkNightScene` 是互不依赖的渲染实现。
- Grain、Reading Veil、Blur、Motion 等只能作为 Scene 主动选择的工具，不能组成所有 Scene 必经的公共流水线。
- 不引入 `[any BackgroundRenderer]`、`[BackgroundEffect]`、Renderer protocol、万能配置字典或不断扩字段的统一背景配置。

## 对原方案的必要修正

### 1. 当前截图测试尚未“锁定四个主题”（历史状态，已失效）

> 本节记录 2026-08-16 制定方案时的截图状态。当前
> `VisualThemeCaptureTests` 已捕获 Default、Neon、Night Bar、Ink Night；必须使用
> 当前测试生成的输出，以下旧文件名不得再作为截图清单。

`LightStatsTests/VisualThemeCaptureTests.swift` 当前只导出：

- `/tmp/sun-gold-panel.png`
- `/tmp/ink-night-panel.png`

它没有覆盖 Glass 和 Bento，也没有保存 reference、执行像素比较或断言视觉差异。因此它现在是人工截图工具，不是自动视觉回归测试。迁移前必须先建立可比较基线，不能把现状描述为已经锁定。

System Glass 依赖 `NSGlassEffectView` / `NSVisualEffectView`、窗口背后内容、macOS 版本和系统外观，不适合跨 OS 做严格像素 golden。四主题都应生成审核截图；严格图像差异门槛优先用于固定 phase 的 Sun Gold 和 Ink Night，Glass/Bento 使用结构测试、非空像素检查和同一环境人工对照。

### 2. Host 不应保留 `contentShape`

背景最终统一 `.allowsHitTesting(false)` 后，`BackgroundHost` 不需要 `.contentShape(...)`。当前根 `HitRetainingHostingView` 已负责吸收面板空白区域 hit/scroll，Popover 根视图也已有自己的 `contentShape`。背景只渲染像素，不再承担事件区域声明。

### 3. AppKit glass 不能进入统一 raster 后处理

`SystemGlassScene` 内含 AppKit-backed `NSGlassEffectView` / `NSVisualEffectView`。不要在 `BackgroundHost` 或 Router 外层统一套用 `.drawingGroup()`、`.compositingGroup()`、Blur、`layerEffect` 或 `distortionEffect`。这些处理只能由需要它们的具体 Scene 放在自己的 SwiftUI raster subtree 上。

Host 的圆角裁切仍可统一；同时必须把 `cornerRadius` 转交给 `SystemGlassScene`，因为 macOS 26 的 `NSGlassEffectView.cornerRadius` 也需要同一几何值。

### 4. 外观设置要类型化，但不能变成新的万能配置

现有 `ThemeAppearanceConfiguration(grainEnabled + dynamics)` 仍默认所有可配置背景拥有同一组能力。最终应把它改为产品层的类型化 sum type，而不是继续向一个 struct 增加 blur、distortion、image、metal 等字段。

建议目标：

```swift
enum ThemeAppearanceConfiguration: Equatable, Sendable {
    case none
    case film(FilmThemeAppearanceConfiguration)
    case noir(NoirThemeAppearanceConfiguration)
}

struct FilmThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double
}

struct NoirThemeAppearanceConfiguration: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double
}
```

这是产品外观设置，不是背景技术描述。它保留现有 `film*` / `noir*` UserDefaults 语义。Router 再将关联值转换为 Scene 自己的强类型输入：

```swift
struct SunGoldSceneInput: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double
}

struct InkNightSceneInput: Equatable, Sendable {
    let grainEnabled: Bool
    let lightFlow: Double
}
```

未来新增一个无用户设置的 PNG 或 Metal Scene，只需使用 `.none`，不扩充公共配置。只有确实新增产品级可调项时，才增加对应产品 appearance case。

### 5. 迁移必须以实际渲染值为准

当前 `BackgroundConfiguration.film/noir.grainOpacity` 都是 `0.32`，但 `FluidMeshBackground.grainOpacity` 实际返回 `0.42` 或 `0`，因此运行时使用的是 `0.42`。`DynamicThemeTests.testMeshBackgroundsShareGrainStrength` 只验证了未被实际消费的 `0.32`。

首轮视觉等价迁移必须复制实际运行路径中的 `0.42`，不能根据看似权威但已失真的配置字段改成 `0.32`。迁移完成后删除这项误导配置和对应旧测试，改测 Scene 输入到 Grain overlay 的真实行为。

## 已确认的当前实现（2026-08-16 历史快照）

以下事实已经从当前 `main`（HEAD `d4a3b26`）核实：

- 上一轮主题拆分提交是 `6447fff refactor(Theme): ThemeDefinition 固定组合，界面/背景/布局拆分`。
- `Light Stats/Models/AppTheme.swift` 已经是稳定产品 ID，不应回滚。
- `Light Stats/Views/Theme/ThemeDefinition.swift` 是四个固定组合的唯一表，但其 `background` 仍是 `BackgroundConfiguration`。
- Glass 与 Bento 都使用 `BackgroundConfiguration.glass`；Film 与 Noir 都进入 `.mesh`。
- `BackgroundConfiguration` 当前包含 `BackgroundKind`、`MeshRendererKind`、`MeshAppearanceSlot`、`MeshMotionConfiguration`、grain、veil、canvas 和 mesh blob 色。
- `ThemeBackgroundView` 统一选择 glass/mesh/solid；所有 mesh 都进入 `FluidMeshBackground`。
- `FluidMeshBackground` 统一拥有 24fps `TimelineView`、phase anchor、Lissajous motion、renderer switch、`.drawingGroup(opaque: true, colorMode: .extendedLinear)`、Reading Veil 和 Grain。
- `ThemeAppearanceSelection.swift` 通过 `background.kind == .mesh` 与 `appearanceSlot` 决定设置布局和绑定。
- `SettingsDetailViews.swift` 暴露 `meshThemeLayout` / `meshLivePreview`，并以 `meshRenderer` 作为视图 identity。
- `PopoverContentView` 直接创建 `ThemeBackgroundView`，同时根视图按 language/theme `.id(...)` 重建完整 chrome。
- `HitRetainingHostingView` 中的 `AnyView` 是 Xcode 26 Release/WMO 编译器崩溃 workaround，只能保留在该局部，不得传播到背景架构。
- 项目与测试目录使用 Xcode synchronized folder group；正常新增 Swift 文件不需要手改 `project.pbxproj`。
- 工作树在制定本方案时已有与本任务无关的改动：`docs/status-bar-fan-core-animation-validation.md` 被修改，`design/` 未跟踪。实现者必须保留，不得回滚、覆盖或顺手提交。

## 不变量与成功标准（历史，非操作性）

> 本节是旧迁移的完成条件，现已被当前实现取代，不得用于指导新修改或验收。
> 其中 `bento`、Bento layout、Glass/Bento 四主题映射以及相关截图要求均已废止。
> 当前主题、Scene、统一 instrument layout 与截图要求以本文顶部“当前状态”为准。

迁移完成后必须同时满足：

1. 四个用户可见产品主题及持久化 raw value 不变：`glass / bento / film / noir`。
2. 冷启动默认仍为 `.noir`；未知旧值仍回落 `.noir`。
3. `ThemeDefinition` 仍是唯一产品组合表，业务视图不通过 `theme == .film/.noir` 选择绘制。
4. 映射固定为：

```text
AppTheme.glass -> ui.glass + BackgroundSceneID.systemGlass + layout.instrument
AppTheme.bento -> ui.bento + BackgroundSceneID.systemGlass + layout.bento
AppTheme.film  -> ui.film  + BackgroundSceneID.sunGold    + layout.instrument
AppTheme.noir  -> ui.noir  + BackgroundSceneID.inkNight   + layout.instrument
```

5. Film/Noir 的四个现有 UserDefaults key、默认值和范围不变：

```text
settings.filmGrainEnabled = true
settings.filmLightFlow    = 0.4, clamp 0...1
settings.noirGrainEnabled = true
settings.noirLightFlow    = 0.4, clamp 0...1
```

6. Sun Gold 与 Ink Night 首轮视觉和运动行为保持不变，包括 24fps、暂停阈值、phase 连续性、颜色、blur、blend、veil、grain 和 layer 顺序。
7. 背景在 Popover 与设置预览中均完全不参与 hit testing。
8. Glass/Bento 继续使用系统 glass，窗口透明配置行为不变。
9. 每个 Scene 可以独立持有或不持有 `TimelineView`；Router/Host 不创建公共时间线。
10. 新增一个无设置的新 Scene 时，需要新增 Scene/Layer/Effect（按需）、`BackgroundSceneID` case、Router 分支，并由产品主题在 `ThemeDefinition` 中选用；不能要求修改旧 Scene 或扩大公共渲染配置。
11. 背景路径中没有新 `AnyView`、renderer protocol、effect 数组或配置字典。
12. `swiftlint --strict`、相关单测、完整测试和 Debug 构建通过，实机主题切换与设置预览通过视觉检查。

## 目标文件结构

命名可按仓库格式微调，但职责不得合并回中心管线：

```text
Light Stats/Views/Theme/
├── Background/
│   ├── BackgroundSceneID.swift
│   ├── BackgroundHost.swift
│   ├── BackgroundSceneRouter.swift
│   ├── Scenes/
│   │   ├── SystemGlassScene.swift
│   │   ├── SunGoldScene.swift
│   │   ├── SunGoldSceneInput.swift
│   │   ├── SunGoldLightField.swift
│   │   ├── InkNightScene.swift
│   │   ├── InkNightSceneInput.swift
│   │   └── InkNightLightField.swift
│   └── Shared/
│       ├── GrainOverlay.swift
│       └── ReadingVeilOverlay.swift
├── FilmThemeAppearanceConfiguration.swift
├── NoirThemeAppearanceConfiguration.swift
├── ThemeAppearanceConfiguration.swift
├── ThemeDefinition.swift
└── ... existing UI/layout files
```

公共工具只在至少一个 Scene 主动消费时存在。不要为了目录对称预建 Blur、Distortion、Motion 或 Metal 抽象。Motion 首轮可以分别留在 Sun Gold / Ink Night Scene 内；如果迁移后确认两者继续使用完全相同且稳定的 phase 算法，再提取纯计算工具，并为其补单测。

`GrainTextureView` 应提升/重命名为与 mesh 无关的 `GrainOverlay`，注释不得再写“mesh themes only”。`ReadingVeilOverlay` 可以共享颜色、中心和半径计算，但 motion offset 必须由各 Scene 传入；Overlay 自己不拥有 Timeline。

## 目标 API 边界

以下是职责示意，不要求逐字照抄：

```swift
enum BackgroundSceneID: String, Equatable, Sendable {
    case systemGlass
    case sunGold
    case inkNight
}

struct BackgroundHost: View {
    let sceneID: BackgroundSceneID
    let appearance: ThemeAppearanceConfiguration
    var cornerRadius: CGFloat = 12
    var configuresWindow = false
    var fallbackMaterial: NSVisualEffectView.Material = .sidebar

    var body: some View {
        BackgroundSceneRouter(
            sceneID: sceneID,
            appearance: appearance,
            cornerRadius: cornerRadius,
            configuresWindow: configuresWindow,
            fallbackMaterial: fallbackMaterial
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }
}
```

Host 不添加 `contentShape`，不添加时间线，不添加颜色、grain、veil、blur、drawing group 或 Metal effect。

Router 使用结构化分支：

```swift
@ViewBuilder
var body: some View {
    switch (sceneID, appearance) {
    case (.systemGlass, _):
        SystemGlassScene(...)
    case (.sunGold, .film(let configuration)):
        SunGoldScene(input: SunGoldSceneInput(configuration))
    case (.inkNight, .noir(let configuration)):
        InkNightScene(input: InkNightSceneInput(configuration))
    case (.sunGold, _):
        SunGoldScene(input: .defaults)
    case (.inkNight, _):
        InkNightScene(input: .defaults)
    }
}
```

不使用 `AnyView`。错误的 scene/appearance 配对属于开发期组合错误；生产 UI 应有确定性默认输入，单测则必须覆盖四个固定 `ThemeDefinition` 映射，防止静默错配。

Router 的 `@ViewBuilder switch` 已经提供 Scene 分支 identity。不要给 Scene 添加 `.id(appearance)` 或 `.id(lightFlow)`；否则用户调整 grain/flow 时会销毁 Scene 的 `@State`，造成 phase 重置或跳变。当前 Popover 根按产品主题整体重建的行为保持不变。

`SettingsManager` 的解析入口应按产品主题工作：

```swift
func themeAppearance(for theme: AppTheme) -> ThemeAppearanceConfiguration
```

不再接受 `BackgroundConfiguration`，不再使用 `appearanceSlot`。设置页面是产品主题配置边界，可以在一个专用 resolver 中识别 Film/Noir；普通业务内容仍不得按 `AppTheme` 选择背景实现。

## Sun Gold 与 Ink Night 的视觉复制契约

迁移第一轮只搬运，不重新设计。源真相是当前代码的实际 modifier 顺序，不是字段命名。

每个动态 Scene 的顺序必须是：

```text
1. Scene canvas 底色
2. Scene 专属 Light Field
3. Light Field 局部 drawingGroup(opaque: true, extendedLinear)
4. Reading Veil overlay
5. Grain overlay（drawingGroup 外，保持锐利）
```

需要逐项从当前实现复制：

- `BackgroundConfiguration.film/noir` 中的 canvas、meshBase、primary、secondary、highlight、veil 和 warmth 色值。
- `MeshMotionConfiguration.film/noir` 的全部振幅、频率和 phase offset。
- `FluidMeshBackground.phase(at:dynamics:)` 的 smoothstep、travel、slow/detail band 公式。
- `motionOffset(...)` 的暂停阈值 `0.02` 与轨迹公式。
- `TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: ...))`。
- dynamics 变化时通过旧速度计算当前 phase，再更新 anchor/date 的连续性逻辑。
- Film/Noir renderer 内所有 frame、offset、blur、opacity、gradient、rotation 和 blendMode 的原始顺序。
- 运行时 grain opacity `0.42`，Sun Gold warmth `0.5`，Ink Night warmth `0`。
- Reading Veil 的四档 opacity、中心跟随比例、start/end radius。

不要在此次迁移中“顺便修正”色值、动画速度、命名不一致或未使用参数。视觉等价通过并删除旧实现后，才允许单独发起视觉调整。

当前每个 `ThemeBackgroundView` 实例拥有自己的 `@State phaseAnchorDate/phaseAnchor`，设置预览和 Popover 因而是独立时钟。迁移后保持这一点；不要建立全局共享时间线。切换产品主题时 Popover 根 `.id(language/theme)` 会重建完整层级，当前 phase 也会重置，首轮迁移不改变该行为。

## 分阶段实施（历史计划，不执行）

### 阶段 0：建立可复现基线

先执行，不改架构：

1. 运行 DynamicTheme、SettingsDefaults 与 VisualThemeCapture 相关测试，确认当前基线可构建。
2. 扩展 `VisualThemeCaptureTests`，导出四个主题，而非只导出 Film/Noir。
3. 在测试中保存并恢复 app theme、language、Film/Noir grain 与 light flow，避免污染 singleton 状态。
4. 为动态背景提供固定 phase 的测试渲染路径，或把 light flow 设为 0 并确认初始 phase 为 0；不能依赖 `RunLoop` 等待后的墙钟 phase 做 golden。
5. 同一台机器、同一 OS、同一系统外观下生成迁移前截图，并记录输出路径。
6. 对 Sun Gold/Ink Night 建立同环境像素差比较；先测量当前重复捕获抖动，再设紧而不 flaky 的阈值，不能凭空指定阈值。
7. Glass/Bento 至少验证尺寸、非空像素和人工截图；不要把桌面依赖的 glass 像素当跨版本稳定 golden。

完成门槛：已有四主题基线；动态两主题的固定 phase 截图可重复；测试不会永久修改用户设置。

### 阶段 1：先建立 Host/Router 边界，以 legacy adapter 保持像素不变

新增 `BackgroundSceneID`、`BackgroundHost`、`BackgroundSceneRouter` 和 `SystemGlassScene`，并让生产 Popover 与设置预览开始通过新边界渲染。此阶段保留 `ThemeDefinition` 作为唯一四主题组合表，但把它的 `background` 改为纯 Scene ID。

对于尚未迁移的动态 Scene，Router 内使用明确命名、明确标记待删除的 `LegacyMeshBackgroundScene`：

```text
.systemGlass -> SystemGlassScene
.sunGold     -> LegacyMeshBackgroundScene(.film)
.inkNight    -> LegacyMeshBackgroundScene(.noir)
```

legacy adapter 可以把 Scene ID 映射回旧 `BackgroundConfiguration` 并调用 `ThemeBackgroundView`，但这个映射只能存在于背景迁移边界，不能重新暴露给业务 View。设置页若暂时仍需旧 `appearanceSlot` / mesh layout，可使用同样明确标记的兼容 resolver；不得把 legacy 类型重新塞回 `ThemeDefinition`。

此阶段 `BackgroundHost` 已统一 `.allowsHitTesting(false)`，不添加 `contentShape`。`SystemGlassScene` 直接封装现有 `GlassBackgroundView`，保持 `configuresWindow`、`fallbackMaterial` 和内部 corner radius 行为。

完成门槛：生产入口已经是 Host/Router；所有四主题像素输出与阶段 0 基线一致；旧 mesh 代码只经 legacy adapter 到达；项目和测试通过。

### 阶段 2：只迁移 Ink Night

新增 `InkNightScene`、`InkNightSceneInput` 和 `InkNightLightField`。Ink Night Scene 自己拥有 Timeline、phase、motion、veil 和选择使用的 Grain overlay；Router 的 `.inkNight` 分支改为直接创建新 Scene，`.sunGold` 继续走 legacy adapter。

逐行复制 Noir 的实际运行路径，不在本阶段抽取 Sun Gold/Ink Night 公共 motion。对固定 phase、grain 开/关和代表性 flow 执行新旧同环境对比。

完成门槛：Ink Night 通过视觉等价与 phase 连续性检查；Sun Gold 仍完全由旧实现渲染；切换两主题无旧 raster 残留。

### 阶段 3：只迁移 Sun Gold

新增 `SunGoldScene`、`SunGoldSceneInput` 和 `SunGoldLightField`。Sun Gold Scene 自己拥有 Timeline、phase、motion、veil 和选择使用的 Grain overlay；Router 的 `.sunGold` 分支改为直接创建新 Scene。

只共享已经由两个 Scene 主动采用且边界明确的具体工具，例如 Grain overlay 或无时间状态的 Reading Veil overlay。不要为了消除少量重复，把两套 Scene 再放回共同 Timeline/motion/renderer 管线。

完成门槛：Sun Gold 通过与 Ink Night 相同的视觉和动画检查；动态 Scene 已无生产路径经过 legacy mesh renderer；System Glass 仍独立直达 AppKit scene。

### 阶段 4：移除设置层的 Mesh 知识

在一个可编译变更中完成：

1. 把 `ThemeAppearanceConfiguration` 改成产品层类型化关联值；增加 Film/Noir 专属配置类型。
2. 将 `SettingsManager.themeAppearance(for:)` 参数改为 `AppTheme`，保留既有 UserDefaults key、默认值和 clamp。
3. 设置页删除 `.mesh`、`appearanceSlot` 和兼容 resolver，按产品 appearance 是否有 controls 决定布局。
4. `meshThemeLayout` / `meshLivePreview` 重命名为技术无关的 `themeWithPreviewLayout` / `backgroundLivePreview`（具体名称可遵循现有风格）。
5. 设置预览继续使用 `BackgroundHost`，identity 使用 `BackgroundSceneID` 或由 `@ViewBuilder switch` 自然管理，不得使用 appearance/lightFlow 作为 `.id`。
6. 更新 DynamicThemeTests，使其断言纯 Scene ID、固定产品组合及产品 appearance 到 Scene input 的映射。

完成门槛：设置生产代码不再读取 `BackgroundKind`、`MeshRendererKind`、`MeshAppearanceSlot` 或 `BackgroundConfiguration`；四主题切换、预览和设置绑定工作；grain/flow 调整不销毁动态 Scene 状态。

### 阶段 5：删除旧模型、更新文档并端到端验证

确认 `rg` 无生产引用后删除：

- `Light Stats/Views/Theme/BackgroundConfiguration.swift`
- `Light Stats/Views/Theme/ThemeBackgroundView.swift`
- `Light Stats/Views/Theme/FilmMeshRenderer.swift`
- `Light Stats/Views/Theme/NoirMeshRenderer.swift`
- `BackgroundKind`
- `MeshRendererKind`
- `MeshAppearanceSlot`
- `MeshMotionConfiguration`
- `FluidMeshBackground`
- 旧 mesh 命名的设置 helper 与测试
- 未使用的 `contentScrim`、`.solid` 分支及失真的 `grainOpacity = 0.32` 配置

如果 `GrainTextureView.swift` 已被迁移成 `GrainOverlay.swift`，删除旧文件，确保只有一份 `GrainTextureCache`。

完成门槛：以下搜索不应有结果（迁移说明文档和历史记录可排除）：

```bash
rg -n "BackgroundConfiguration|ThemeBackgroundView|FluidMeshBackground|BackgroundKind|MeshRendererKind|MeshAppearanceSlot|MeshMotionConfiguration|meshThemeLayout|meshLivePreview|LegacyMeshBackgroundScene" \
  "Light Stats" LightStatsTests
```

随后完成文档与端到端验证：

1. 同步更新根目录 `AGENTS.md` 与 `CLAUDE.md`，两者必须保持镜像。
2. 更新其中的项目树与主题说明：`ThemeDefinition` 的 background 是 Scene ID，背景由 Host/Router/Scenes 负责。
3. 不修改 `PROJECT_MEMORY.md` 的历史内容；如实现形成新的长期决策，可另追加一条取代旧 `BackgroundConfiguration` 描述的记录，但不能删除历史。
4. 运行 lint、测试、构建和 `./debug-run.sh`。
5. 实机检查四主题、两类设置预览、动态开/关/五档速度、grain 开/关、Popover 空白区点击和滚轮隔离。
6. 检查 macOS 26 Glass 与旧系统 fallback（可用当前可用系统验证，无法覆盖的系统必须在结果中说明）。

## 测试与验证命令（历史命令，不作为当前截图流程）

先用窄测试确认架构和默认值，再跑全量：

```bash
xcodebuild test -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" -destination 'platform=macOS' \
  -only-testing:LightStatsTests/DynamicThemeTests \
  -only-testing:LightStatsTests/SettingsDefaultsTests \
  -only-testing:LightStatsTests/VisualThemeCaptureTests

swiftlint lint --strict

xcodebuild test -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" -destination 'platform=macOS'

./debug-run.sh
```

按照仓库规则，UI 架构迁移完成后必须运行 `./debug-run.sh`，并实际打开 Popover 与 Settings 检查。

历史人工验收矩阵（已被当前四个可见主题取代）：

| 产品主题 | Scene | 必查项 |
|---|---|---|
| Default / Glass | System Glass | 系统材质、圆角、窗口透明、无背景命中 |
| Bento | System Glass | 与 Glass 共享背景但保留 Bento layout/UI |
| Sun Gold | Sun Gold | 暖色 S 曲线、24fps、5 档 flow、grain、veil 顺序 |
| Ink Night | Ink Night | 冷色纵向光柱、24fps、5 档 flow、grain、veil 顺序 |

所有动态主题还应检查：

- flow 从非零切到 0 时停在当前 phase，不跳回初始画面。
- flow 从 0 恢复时从暂停 phase 连续运动。
- flow 在不同非零档位间切换时没有明显位置跳变。
- 设置预览和 Popover 各自运动，不共享全局状态。
- 关闭 grain 后光场与 veil 不受影响；开启后颗粒保持锐利，不被 light field blur。
- 快速切换 Film/Noir 不出现旧 raster 缓存残留。

## 禁止事项（历史迁移约束）

- 不回滚 `AppTheme` 产品 ID 收敛或 `ThemeDefinition(ui + background + layout)`。
- 不新增用户可见的背景选择器或 UI/background 自由组合。
- 不让普通业务 View switch `AppTheme` 来决定背景绘制。
- 不用 `AnyView` 解决 Router 分支类型问题。
- 不创建统一 renderer protocol、effect pipeline、effect 数组或 `[String: Any]` 配置。
- 不在 Host 外层统一 rasterize AppKit glass。
- 不让 Grain、Veil 或 Motion 自动套到所有 Scene。
- 不在视觉等价迁移中顺便调色、调速、改 blur 或替换 blend mode。
- 不修改 pbxproj，除非实际构建证明 synchronized folder 没有收录新文件。
- 不回滚或覆盖实施开始前已有的脏工作树内容。

## 后续扩展应满足的证明

架构完成后，用设计审查而非产品代码验证以下例子均无需改变旧 Scene：

- PNG 背景：新增 `ImageBackgroundScene`，在 Router 增加分支；不经过 Grain/Veil/Motion。
- 无底色熔融金属 + `0.3` Blur：新增独立 Scene，仅对金属 raster subtree 应用 blur。
- 拼贴图片 + Metal 扭曲：新增 Scene，在内部对 SwiftUI raster layer 使用 `distortionEffect` / `layerEffect`；不尝试处理 `SystemGlassScene`。
- 静态纯色：新增 Scene 直接产生颜色像素，不需要 Timeline 或 renderer protocol。

如果新增这些 Scene 需要向 `BackgroundHost` 增加 image、mesh、grain、motion、blur 或 shader 参数，说明边界再次泄漏，应退回 Scene 内部设计。

## 相关资料

- Apple `allowsHitTesting(_:)`: https://developer.apple.com/documentation/swiftui/view/allowshittesting(_:)
- Apple `ViewBuilder`: https://developer.apple.com/documentation/swiftui/viewbuilder
- Apple `Canvas`: https://developer.apple.com/documentation/swiftui/canvas
- Apple `compositingGroup()`: https://developer.apple.com/documentation/swiftui/view/compositinggroup()
- Apple `layerEffect`: https://developer.apple.com/documentation/swiftui/view/layereffect(_:maxsampleoffset:isenabled:)
- Apple `distortionEffect`: https://developer.apple.com/documentation/swiftui/view/distortioneffect(_:maxsampleoffset:isenabled:)

## 接手后的第一个动作（已废止，不执行）

> 以下内容是旧方案原文，仅为保留设计历史。迁移已经完成，legacy adapter 路径和
> Bento 时代基线不再是当前工作的起点。当前截图验证应直接运行现有
> `VisualThemeCaptureTests`，覆盖 Default、Neon、Night Bar、Ink Night。

不要直接删除旧实现。先读取本文件列出的当前源文件，检查工作树仍有哪些用户改动，然后执行“阶段 0”：把视觉捕获扩展到四主题、固定动态 phase、生成同环境迁移前基线。只有基线可重复后，才通过 legacy adapter 建立 Host/Router 生产边界，并按 Ink Night、Sun Gold 的顺序逐个迁移。

# 背景 Scene 架构 · 现行实现

> 状态：架构迁移已完成并落地。本文描述**现行软件实现**，不再是迁移方案。
> 原迁移计划（阶段 0–5、legacy adapter、Bento 基线）已从本文移除；需要的设计历史在
> git 提交记录中（迁移收尾提交 `46fbd6b` 起，主题收缩为 4 个、删除 Bento 与灰纱）。
> 对应代码：`Light Stats/Views/Theme/`（`Background/` 目录）。

## 产品主题

用户可见 4 个预设（`AppTheme.visibleCases`，展示顺序即下方顺序），`dataPaper` 保留但隐藏：

| 产品主题 | 界面名称 | UI tokens | 背景 Scene | 布局 |
|---------|---------|-----------|-----------|------|
| `glass` | Default | `.glass` | `.systemGlass` | `.instrument` |
| `film` | Neon | `.film` | `.sunGold` | `.instrument` |
| `bar` | Amber | `.bar` | `.bar` | `.instrument` |
| `noir` | Ink Night | `.noir` | `.inkNight` | `.instrument` |
| `dataPaper`（隐藏） | Data Paper | `.dataPaper` | `.technicalPaper` | `.instrument` |

- 冷启动默认 `.noir`；UserDefaults 中缺失 / 未知 / 已隐藏的旧值经 `AppTheme.resolve` 回落 `.noir`。
- `AppTheme` 只是产品预设 ID。组合唯一入口是 `ThemeDefinition`，固定写出 `ui + background + layout`；
  业务 View 只消费解析结果，禁止 switch `AppTheme`。

## 背景架构

```
Views/Theme/Background/
├── BackgroundSceneID.swift       systemGlass / sunGold / bar / inkNight / technicalPaper
├── BackgroundHost.swift          容器职责：填满尺寸、连续圆角裁切、窗口上下文转交、
│                                 .allowsHitTesting(false)；无 contentShape、无时间线、无效果
├── BackgroundSceneRouter.swift   @ViewBuilder switch 唯一 Scene 创建入口（无 AnyView）
├── Scenes/
│   ├── SystemGlassScene.swift    AppKit 玻璃（NSGlassEffectView / NSVisualEffectView），
│   │                             接收 cornerRadius / fallbackMaterial / configuresWindow
│   ├── SunGoldScene.swift        + SunGoldSceneInput / SunGoldSceneConfiguration / SunGoldLightField
│   ├── BarScene.swift            + BarSceneInput / BarSceneConfiguration / BarLightField
│   ├── InkNightScene.swift       + InkNightSceneInput / InkNightSceneConfiguration / InkNightLightField
│   └── TechnicalPaperScene.swift 静态 Canvas 场景，无动态效果
└── Shared/
    ├── GrainOverlay.swift        + GrainOverlayConfiguration + GrainTextureCache
    ├── ReadingVeilOverlay.swift  + ReadingVeilConfiguration
    ├── FlowAnimationConfiguration.swift
    └── LightFieldLayerConfiguration.swift
```

关键边界：

- **Router 用结构化分支**：`(.systemGlass, _)`、`(.sunGold, .film(config))`、`(.bar, .bar(config))`、
  `(.inkNight, .noir(config))`，其余组合回落对应 Scene 的 `.defaults`。错误的 scene/appearance
  配对是开发期组合错误，生产 UI 有确定性默认输入。
- **动态 Scene 自己拥有渲染栈**：各自持有 `TimelineView(.animation(minimumInterval: 1/24, paused:))`、
  phase 连续性逻辑、Light Field、对 Light Field 局部的 `drawingGroup`、Reading Veil，
  以及 drawingGroup 之外的 Grain overlay（保持锐利）。Host / Router 不建公共时间线。
- **外观设置是产品层类型化 sum type**（`ThemeAppearanceConfiguration`）：
  `.none` / `.film(FilmThemeAppearanceConfiguration)` / `.bar(BarThemeAppearanceConfiguration)` /
  `.noir(NoirThemeAppearanceConfiguration)`，每个配置含 `grainEnabled` + `lightFlow`（0...1）。
  `SettingsManager.themeAppearance(for: AppTheme)` 是唯一解析入口，保留
  `settings.{film,bar,noir}{GrainEnabled,LightFlow}` 的 UserDefaults 语义。
- **Scene 不做 `.id(appearance)` / `.id(lightFlow)`**：grain/flow 调整不会销毁 Scene 的
  `@State`、不会重置 phase。Popover 根按产品主题整体重建的行为保持不变；设置预览与 Popover
  各自拥有独立时钟，不共享全局 phase。
- **SystemGlassScene 是 AppKit-backed**：不进统一 raster 后处理；`cornerRadius` 转交给它，
  因为 `NSGlassEffectView.cornerRadius` 需要同一几何值。

## 已删除的旧概念（生产代码零引用）

`BackgroundConfiguration`、`ThemeBackgroundView`、`FluidMeshBackground`、
`BackgroundKind` / `MeshRendererKind` / `MeshAppearanceSlot` / `MeshMotionConfiguration`、
`meshThemeLayout` / `meshLivePreview`、`LegacyMeshBackgroundScene`、Bento 专属布局与
`BentoCard` / `QuickStatCard`、灰纱主题。全产品只有 instrument 一种布局；背景统一
`.allowsHitTesting(false)`，不再承担任何事件区域声明。

## 验证

- `DynamicThemeTests` 断言纯 Scene ID、固定产品组合及产品 appearance → Scene input 映射。
- `VisualThemeCaptureTests` 覆盖当前四个用户可见主题，截图以测试实际报告的输出为准。
- 新增无设置的新 Scene 只需：新 Scene 文件（可无 Timeline）、`BackgroundSceneID` case、
  Router 分支、`ThemeDefinition` 选用；不要求改旧 Scene 或扩大公共渲染配置。

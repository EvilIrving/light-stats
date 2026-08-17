# Project Memory

## 官方模型价格估算基准（pi） · 2026-08-17 13:38 CST · agent

为 pi 的 `~/.pi/agent/models.json` 配置成本估算时，采用官方上游公开价格作为参考，单位均为 USD / 1M tokens。当前配置使用的是 `https://api.shu.cool/v1` 中转，因此这些数字只用于 pi 的本地成本估算，不代表中转服务的实际扣费；中转价格需要另行确认。

- OpenAI 官方标准价：`gpt-5.6-sol` input 5 / output 30 / cacheRead 0.50 / cacheWrite 6.25；`gpt-5.6-terra` 2 / 12 / 0.20 / 2.50；`gpt-5.6-luna` 0.20 / 1.20 / 0.02 / 0.25；`gpt-5.5` 5 / 30 / 0.50 / 0。输入上下文超过 272K 时，分别使用长上下文价：Sol 10 / 45 / 1 / 12.5，Terra 4 / 18 / 0.40 / 5，Luna 0.40 / 1.80 / 0.04 / 0.50，GPT-5.5 10 / 45 / 1 / 0。
- DeepSeek 官方当前同时按高峰/非高峰计价：`deepseek-v4-flash` 非高峰 input 0.22 / cacheRead 0.007 / output 0.66，高峰 0.44 / 0.014 / 1.32；`deepseek-v4-pro` 非高峰 0.66 / 0.022 / 1.98，高峰 1.32 / 0.044 / 3.96。官方没有单独的 cacheWrite 价格，pi 中填 0。为避免低估，`models.json` 采用高峰价。
- xAI 官方标准价：`grok-4.5` input 2 / cacheRead 0.30 / output 6，`grok-4.6` 2 / 0.50 / 6；prompt 达到 200K 时使用长上下文价：Grok 4.5 为 4 / 0.60 / 12，Grok 4.6 为 4 / 1 / 12。两者均无单独 cacheWrite 价格，pi 中填 0。

价格来源：OpenAI <https://developers.openai.com/api/docs/pricing>；DeepSeek <https://api-docs.deepseek.com/quick_start/pricing>；xAI <https://docs.x.ai/developers/pricing>。价格可能变化，后续更新 `models.json` 前应重新核对官方页面。

## 主题以 ThemeDefinition 固定组合，不向用户暴露混搭 · 2026-08-16 17:01 · Grok

这条取代 2026-08-16 16:36「主题拆成 UITheme + BackgroundTheme 两个正交维度」。那次把界面和背景做成了可独立持久化的产品维度，并准备以后加背景选择器。产品决定不走这条路：用户仍然只看见 `glass / bento / film / noir` 四个预设，不出现背景选择或主题组合。

正确边界是：`AppTheme` 只是产品预设 ID；`ThemeDefinition` 是唯一组合入口，固定写出 `ui + background + layout`；`UITokens` 管文字 / surface / signal / divider / accent / 卡片与布局语义；`BackgroundConfiguration` 管 `glass / mesh / solid`、canvas、mesh 色、grain、dynamics；Film / Noir 光场是独立 Renderer。业务 View 只读解析结果，禁止 `theme == .film` / `theme == .noir`。`aurora` / `paper` 不再映射到 film，未知键回落到 noir。以后加第五个主题只改 `ThemeDefinition` 表，复用或新增内部能力，不改 Overview / Cleanup / 卡片，也不把组合能力做成设置项。

## 主题拆成 UITheme + BackgroundTheme 两个正交维度 · 2026-08-16 16:36 · Grok

`AppTheme` 不再同时拥有布局/配色和背景策略。它现在只是四个策展配对：`glass = glass UI + glass 背景`，`bento = bento UI + glass 背景`，`film = film UI + film 背景`，`noir = noir UI + noir 背景`。界面半边是 `UITheme`（layout、ink、surface、tab、signal；`usesBentoLayout` / `usesVibrantSurfaces` 留在这里）。背景半边是 `BackgroundTheme`（`glass / film / noir`，外加 `BackgroundKind`：`glass / mesh / solid`）。

`ThemeTokens` 只服务界面，禁止再长回 `usesGlass` / `usesMesh` / `canvas` / `meshBlob*` / `grainOpacity`。`ThemeBackgroundView` 只接收 `BackgroundTokens`，按 `kind` 选 renderer，按 `BackgroundTheme` 选 Film/Noir 光场，完全不知道 `UITheme` 或 `AppTheme`。设置仍用一个配对选择器，但已分别持久化 `settings.appTheme` 与 `settings.backgroundTheme`。读档时若已有独立的 background 键会尊重它（因此数据层已经能混搭）；改配对选择器仍会把 background 写回该配对，直到出现独立背景选择器。

以后加背景只新增 `BackgroundTheme` case + renderer + `BackgroundTokens` 工厂。不要回头改 Overview / Cleanup / 卡片，也不要把背景判断写回 `ThemeTokens.ui`。自由组合的下一步是设置里拆开两个选择器，并停止在 `appTheme.didSet` 里覆盖 `backgroundTheme`。

## macOS 26 Popover 滚轮隔离与动态主题基线 · 2026-08-10 10:48 · Codex

macOS 26 会让非透明 `NSPanel` 中未被 SwiftUI 子视图处理的滚轮事件继续落到桌面或下方窗口；用户报告 macOS 17 没有同样现象。稳定修复边界是在 `HitRetainingHostingView` 中保留现有 `hitTest` 全边界兜底，并在宿主层吸收最终未处理的 `scrollWheel`，而实际 `ScrollView` 等后代仍通过正常命中测试接收滚动。不要通过增加不透明绘制层、改变主题材质或强制 `.glass` 来解决事件穿透，因为事件隔离与视觉渲染必须互不耦合。

本次出现的“修复滚动后 Sun Gold 变粉”并非滚轮补丁改变颜色。第一张期望截图对应 `/Applications/Light Stats.app` 中约在提交 `49ae62a` 后构建的深色动态版本，而重新构建当前源码时启用了提交 `be82e1d` 的浅粉色静态 artwork 重构；该提交曾把 Sun Gold 从深色动态网格和浅色文字改为浅色静态象牙/玫瑰/珊瑚底，并将其首选配色方案从深色改为浅色。以后遇到“改一行后整个 UI 变样”时，应先比较正在运行的 App 构建来源、时间和源码提交，避免把重新构建显露出的既有提交误判为当前补丁的副作用。

当前确认的产品基线是保留 `49ae62a` 风格的深色动态 Sun Gold 与 Ink Night：动态网格、胶片颗粒、浅色文字，以及可持久化的 `filmGrainEnabled`、`filmLightFlow`、`noirGrainEnabled`、`noirLightFlow` 设置。主题应继续覆盖 Popover、About、Toast、Update 和权限提示；不得把这些窗口静默固定为默认玻璃主题。视觉回归应同时检查动态主题截图和 macOS 26 实机滚轮隔离，不能只凭编译成功判断。

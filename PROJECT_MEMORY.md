# Project Memory

## ScrollDirectionService 的 IOHID 改写机制与坑 · 2026-08-18 17:10 CST · agent

`ScrollDirectionService`（滚动方向反转 / 关加速度 / 触控板反转）是重建成本最高的服务之一：正确性依赖一堆无法从代码表面看出的私 API 行为，之前的踩坑记录散在代码注释里，这里收敛成结论。

**机制**：我们用 session 级 tap（`.cgSessionEventTap` + `.headInsertEventTap`）。开启 Natural Scrolling 后，滚动方向的「权威来源」是事件底层的 IOHIDEvent 浮点值，不是 CGEvent 的 delta 字段——只改 CGEvent 会被系统从 IOHID 重新派生覆盖、方向翻不动。所以反转必须 `CGEventCopyIOHIDEvent` 取出底层 IOHIDEvent，改写其 ScrollX/ScrollY 浮点，同时同步改写 CGEvent 三个 delta 字段。

**三个已验证的坑（不要回退）**：
1. **IOHID ABI**：64 位 Mac 上 IOHIDFloat 是 Double，`IOHIDEventGet/SetFloatValue` 必须按 Double 声明；按 Float 声明会读到错位垃圾值，方向静默失效。
2. **读-写顺序**：写任何字段前必须一次性读完所有原始 delta。设置 DeltaAxis 会让系统按固定倍率（约 8×）重算 PointDelta/FixedPt，边读边写会读到重算值、把方向二次翻回原样。
3. **IOHID 二次拷贝**：改完 CGEvent 字段后必须「重新」`CGEventCopyIOHIDEvent` 再写 IOHID——改 CGEvent 会重建底层 IOHIDEvent，沿用旧拷贝会落在脱钩对象上失效。

**关加速度的语义（对照开源定案）**：只归一化垂直 `DeltaAxis1`（行步进），`point/fixed/IOHID` 只做方向翻转、不归一化。之前试过把 `scrollLines/|line|` 套到所有字段，会把原始像素量一起缩放、手感发虚——这是 Scroll Reverser `discreteAdjust` 分支刻意避免的。`scrollLines` 独立于 `stepMultiplier`（不再叠乘），`stepMultiplier` 也不作用于连续设备（触控板/Magic Mouse 只做方向反转）。

**参考来源与边界**：反转照 Scroll Reverser `MouseTap.m`（同为 session tap），关加速度语义照 UnnaturalScrollWheels `ScrollInterceptor.swift`（HID 级 tap + `signum*scrollLines`）。注意 Scroll Reverser 源码里水平 IOHID 写入误用了垂直乘数 `vmul` 而非 `hmul`，这是它的 bug，不要抄——我们已用正确的 `hmul`。设备分类只用 `isContinuous`（与 UnnaturalScrollWheels 默认一致）；Scroll Reverser 用 gesture tap 数手指区分触控板 vs 连续鼠标的方案被否决（生命周期/权限/兼容风险大，且我们的设置把触控板/Magic Mouse 当同一组）。

**已补的健壮性**：tap 被系统禁用或睡眠唤醒后会自动恢复（`didWakeNotification` 立即 + 1 秒延迟重试；port 失效则在同线程重建 tap）。

**仍待真机验证**（无头环境测不了手感）：慢/快滚产生的 ±1/±2/±3/±5 归一化手感、触控板惯性阶段方向连续性、睡眠唤醒恢复、Logitech Options 等第三方驱动可能错误标记 continuous 的边界。

Popover 的视觉主角必须是健康分数、实时指标、状态和趋势；tab track、selected state、工具栏按钮、well 与 hover wash 只是辅助导航和交互反馈。它们不得成为 panel 最深、最亮、饱和度最高或对比最强的区域，否则会倒置信息层级并抢走 instrument data 的注意力。

选中态应依靠克制的字重变化、很轻的洗色或细指示线表达，不使用高对比实心舱、大面积深色轨道或高饱和渐变。这个原则适用于所有主题，不只 Sun Gold / Neon。允许 tab track 不等于允许它成为视觉板块；评审时必须把控件放回完整 panel 中比较注意力，而不能只看控件局部是否“好看”。

## 禁止内容暗板 / 阅读卡片 · 2026-08-18 15:35 CST · Grok

产品硬约束：任何主题都不得给 instrument 读数盖一层填色卡片、烟玻璃或「阅读板」来解决对比度。字直接坐在场景上。这条不只针对 Neon。

起因：Neon 配色改成暖金后，金字叠在 SunGold 高光上看不见，曾用 `surfaceFill` 深琥珀半透明板垫在 `PanelSection` 后面。用户明确否决，并要求写成全主题约束。Bento 卡片已删除，禁止以「阅读面」名义加回来。

允许：tab track、well（进度槽）、hover 浅洗。不允许：section / row / popover 本体的填色圆角底板。Neon 的 `surfaceFill` 必须保持 `.clear`。对比度只能靠墨水相对场景，不能靠加一层板。

Neon 后续补充：不要荧光。禁止高饱和高亮金 / 柠 / 青 / 粉，禁止文字和 sparkline 辉光。色板是哑光黄铜、赭石、铁锈，不是灯管。夜色酒吧可以保留灯管辉光，Neon 不行。

## 主题阵容收缩：Ash Veil 与 Bento 已删除 · 2026-08-18 · agent

产品决定删除 `ashVeil`（灰纱）与 `bento`（Bento 网格）两个主题，只剩 4 个可见预设：`glass`（默认）/ `film`（霓虹）/ `bar`（夜色酒吧）/ `noir`（墨夜），另有隐藏的 `dataPaper`。

- `bento` 的删除范围包括：`AppTheme.bento` case、`ThemeDefinition.bento`、`UITokens.bento`、`ThemeLayout.bento` 与 `usesBentoLayout` 布局分叉（现已不存在，全产品只有 instrument 布局）、`BentoCard` / `QuickStatCard` 组件、Overview / Cleanup 的 bento 分支、`docs/screenshots/bento/`。
- 设置窗的 `appThemed` 锁从 `.bento` 换成 `.glass`（同为 vibrant + 系统控件底，视觉等效）。
- 迁移行为：已存储的 `"ashVeil"` / `"bento"` 偏好经 `AppTheme.resolve` 回落到 `.noir`，有回归测试覆盖。
- 后续若再加主题，改 `ThemeDefinition` 组合表即可，业务视图（Overview / Cleanup / 行组件）已无布局分叉。

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

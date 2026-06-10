# AI 用量监控 Plan（Phase 1：Claude Code + Codex）

## 目标与范围

在概览页（Overview Tab）显示 Claude Code 与 Codex 的订阅用量（5h 窗口 + 1 周窗口），可在设置中分别关闭。个人使用，不追求产品级覆盖。

**做：**
- Claude Code 用量：5h / 7d utilization + 重置时间
- Codex 用量：primary（5h）/ secondary（weekly）窗口 + 重置时间
- 概览页各一张卡片；两个 provider 都关闭时整个区块不渲染
- 设置页：两个独立开关（关闭 = 完全不轮询、不创建任何请求）
- 独立轮询节奏，与系统监控的 1–5 秒刷新完全分离，间隔可配置（不硬编码）

**不做（明确排除）：**
- 其他 provider（Cursor / Qwen / MiniMax 等）
- 浏览器 cookie 抓取、WebView、Full Disk Access
- OAuth token 刷新流程（凭证由 Claude Code / Codex CLI 自己维护，我们只读）
- 状态栏显示（如以后想要，作为 Phase 2 单独做）
- token 消耗成本统计（JSONL 解析）

## 数据来源（已验证）

### Claude Code
- 凭证：Keychain generic password，service = `Claude Code-credentials`（本机已确认存在）。JSON 内 `claudeAiOauth.accessToken`。
- 请求：`GET https://api.anthropic.com/api/oauth/usage`
  - `Authorization: Bearer <accessToken>`
  - `anthropic-beta: oauth-2025-04-20`
- 响应：`five_hour` / `seven_day` 对象，各含 `utilization`（0–100）与 `resets_at`（ISO8601）。另有 `seven_day_opus` / `seven_day_sonnet` 等字段，Phase 1 忽略，解码时用 `decodeIfPresent` 容错。
- 401 处理：标记 `tokenExpired`，UI 提示"运行一次 claude 以刷新凭证"。不自己刷新。
- Keychain 读取：优先 Security.framework（首次会弹一次钥匙串授权，选"始终允许"即可）；若想免弹窗，备选方案是子进程调用 `/usr/bin/security find-generic-password -s "Claude Code-credentials" -w`（CodexBar 的 prompt-free 路径）。Phase 1 先用 Security.framework，遇到问题再切。

### Codex
- 凭证：`~/.codex/auth.json`（本机已确认存在），取 `tokens.access_token` 与 `tokens.account_id`。
- 请求：`GET https://chatgpt.com/backend-api/wham/usage`
  - `Authorization: Bearer <access_token>`
  - `ChatGPT-Account-Id: <account_id>`
  - `Accept: application/json`
- 响应（✅ 2026-06-10 已用真实响应核对，HTTP 200）：

  ```json
  {
    "plan_type": "plus",
    "rate_limit": {
      "primary_window":   { "used_percent": 1,  "limit_window_seconds": 18000,  "reset_after_seconds": 18000, "reset_at": 1781095404 },
      "secondary_window": { "used_percent": 94, "limit_window_seconds": 604800, "reset_after_seconds": 66212, "reset_at": 1781143616 }
    }
  }
  ```

  - `reset_at` 是 **Unix epoch 秒**（不是 ISO8601），用 `Date(timeIntervalSince1970:)` 转换。
  - `used_percent` 是数字（实测整数，模型用 `Double` 容错）。
  - Codable 模型据此定义：`CodexUsageResponse { rate_limit: { primary_window, secondary_window } }`，窗口字段 `used_percent` / `limit_window_seconds` / `reset_after_seconds` / `reset_at`。
  - 解码仍全部 `decodeIfPresent`，单个窗口解码失败不影响另一个；`plan_type` 可顺带显示（可选）。
- 401 处理：先重读一次 auth.json（Codex CLI 可能已刷新过 token）再试一次；仍 401 则 `tokenExpired`，提示"运行一次 codex 登录态会自动刷新"。

### 前提检查
- ✅ 已确认 target 未开 App Sandbox：`LightStats.entitlements` 中 `com.apple.security.app-sandbox = false`，pbxproj Debug/Release 均 `ENABLE_APP_SANDBOX = NO`（Hardened Runtime 开启，但不影响读 `~/.codex/auth.json` 和 Keychain）。
- ✅ 已确认 `~/.codex/auth.json` 结构：`tokens.access_token` / `tokens.account_id` / `last_refresh`，与上文一致。

## 架构

全部新增，不改动 SystemMonitor 的职责：

```
Models/AIUsageInfo.swift          # 数据模型
Services/ClaudeUsageService.swift # Claude 拉取 + 解码
Services/CodexUsageService.swift  # Codex 拉取 + 解码
ViewModels/AIUsageMonitor.swift   # 独立轮询 + 状态发布
Views/Popover/Components/AIUsageCard.swift  # 概览页卡片
```

### 数据模型（按"窗口"建模，不硬编码 5h/1w 语义）

```swift
enum AIProvider: String { case claude, codex }

struct UsageWindow {
    let label: String          // "5h" / "1w"（本地化 key）
    let usedPercent: Double    // 0–100
    let resetsAt: Date?
}

enum ProviderFetchState {
    case idle                  // 未拉取过
    case loaded(ProviderUsageSnapshot)
    case stale(ProviderUsageSnapshot)   // 上次成功数据 + 本次失败
    case error(AIUsageError)   // tokenExpired / credentialsMissing / network
}

struct ProviderUsageSnapshot {
    let provider: AIProvider
    let windows: [UsageWindow]
    let fetchedAt: Date
}
```

### AIUsageMonitor（核心）

- `@MainActor final class AIUsageMonitor: ObservableObject`，单例或挂在 AppDelegate，与 `SystemMonitor` 平级。
- 自己的 `Timer`，间隔来自 `SettingsManager.aiUsageRefreshInterval`，与系统监控的 `refreshRate` 无关。
- 启停规则：
  - 两个开关都关 → timer 不存在，零开销
  - 任一开关打开 / 间隔变更 → 重建 timer
  - 设置 `didSet` 里通知 monitor（沿用 SettingsManager 现有 `didSet` + save 模式）
- 每个 tick：对启用的 provider 并发 `async let` 拉取，网络在后台，结果回 MainActor 发布。
- 失败时保留上次 snapshot 转为 `.stale`（带 fetchedAt 显示"x 分钟前"），不清空 UI。
- popover 打开时若距上次成功 > 60s 触发一次即时刷新（避免打开看到旧数据，也避免频繁开关 popover 刷爆接口）。
- 最近一次 snapshot 序列化进 UserDefaults，启动即显示旧数据（标记 stale）等首次拉取。

### 设置项（SettingsManager 扩展）

```swift
@Published var aiMonitorClaudeEnabled: Bool   // 默认 false（opt-in）
@Published var aiMonitorCodexEnabled: Bool    // 默认 false
@Published var aiUsageRefreshInterval: AIRefreshInterval  // .m1/.m5/.m15，默认 .m5
```

Key 命名沿用 `settings.*` 前缀。设置页加一个 "AI Usage" 分组：两个 Toggle + 间隔 Picker。

### UI（OverviewTabView）

- 网络卡片下方新增区块：每个启用的 provider 一张 `BentoCard`（沿用现有 Bento 风格）。
- **卡片可隐藏 + 布局一致性**：开关与卡片一一对应——设置里关掉哪个 provider，对应卡片就从概览页移除；两个都关则整个区块消失，不留空白占位。实现上直接在 OverviewTabView 现有 `VStack(spacing: 12)` 里用 `if settings.aiMonitorClaudeEnabled { ... }` 条件渲染，SwiftUI 会自动收紧间距，其余卡片布局不变。新卡片的标题/图标/内边距/字号全部走 `BentoCard` 现有参数，不引入新的视觉样式。
- 卡片内容：provider 名 + 两行窗口：label、进度条（颜色沿用 `colorForUsage` 的 绿/黄/红 阈值）、百分比、reset 倒计时（"3h 12m 后重置"，用相对时间，不做秒级跳动）。
- 状态展示：
  - `idle/loading`：占位 "—"
  - `stale`：数据照常显示 + 灰色小字 "x 分钟前"
  - `tokenExpired/credentialsMissing`：卡片内一行提示文案，不弹窗
- 本地化：en/zh 各加 ~8 个 key（标题、窗口 label、错误提示、重置文案）。

## 实施步骤

1. **Services + Models**：两个 fetcher（纯 async 函数，URLSession.shared），decode 模型，错误枚举。先用临时 CLI/单测对真机凭证跑通两个接口，核对 Codex 响应字段名。
2. **AIUsageMonitor + SettingsManager 扩展**：timer 生命周期、并发拉取、snapshot 缓存。
3. **UI**：AIUsageCard、OverviewTabView 接入、设置页分组、本地化。
4. **打磨**：stale/错误态、popover 打开即时刷新、启动恢复缓存。

## 风险

- 两个接口都是非公开接口，字段可能变 → 全量 `decodeIfPresent`，解码失败降级为 stale 而非崩溃。
- Anthropic 对消费者 OAuth token 用于第三方工具的 ToS 灰色地带 → 只读 usage、低频轮询（≥1min）、个人使用，与全部同类工具一致；知悉即可。
- Keychain 授权弹窗体验 → 首次弹一次属预期；若 ACL 拒绝读取，切 `/usr/bin/security` 子进程方案。

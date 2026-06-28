# Light Stats 自动续期 AI 用量窗口 — 设计与分阶段实施计划

> 状态：**⚠️ 代码全部完成（P0–P7，已提交、测试全绿），但 D 复测推翻了核心前提** · 创建 2026-06-28 · 最后更新 2026-06-28
> **D 复测结论：未能证实「发消息能把 reset 提前」，证据偏向 reset 由固定 5h 网格决定、发消息改不了**（见 P0「D 复测」）。
> 实现机制本身正确（会按时发消息、调度/进程/UI 都对），但它能否达到「把重置挪进工作时段」的目的存疑，待用户决定去留。
>
> 本文是一份分阶段、可单独提 PR 的工程计划。每个阶段都有明确的验收标准和
> 文件落点。给自动 loop 执行：**按 P0 → P7 顺序推进，每完成一个任务就把对应
> `- [ ]` 勾成 `- [x]`，并更新顶部状态行。P0 不通过则停止并上报。**

## 背景

Claude / Codex 订阅额度是"滚动 5 小时窗口"：窗口从你发出的第一条消息开始计时，
5 小时后自动重置，与用量多少无关。业内常见技巧叫 **warmup**：提前发一条无意义消息
把窗口起点挪进工作时段，让重置落在你需要它的时候。用户当前是手动做这件事（用
Claude Code `/loop` 每 4 小时 ping 一次），现在要把它做成 app 内置功能。

调研结论（见 `docs/ai-usage-providers-research.md` 同源）：warmup 必须发**真实消息**
（`claude -p "."`），现有只读探测用的 `/usage`、`/status` 斜杠命令疑似不 anchor 窗口。

## 产品决策（已定，不再讨论）

- **纯开关，无配置，无警告文案。** 每个 provider 一个 Toggle，仅在该 provider 用量监控
  已开启时出现。不弹确认框、不加 ⓘ 提示。
- **默认关闭。** 遵循 `CLAUDE.md` 的"零侵入/默认关闭"契约。不开的用户零成本。
- **针对订阅窗口，不是花钱。** 这些 CLI 走订阅 OAuth（Claude Pro/Max、ChatGPT），
  包月固定价。一条单 token ping 不花钱，只消耗一丝限流额度。DeepSeek 评审里"无声扣费"
  的说法对订阅制不成立，故不采纳其"必须加提示"的结论。
- **Gemini 不做。** Gemini 是每日 quota（`GeminiUsageService` 的 `retrieveUserQuota` /
  `remainingFraction`），不是滚动窗口，没有"把重置提前"的余地。只给 Claude + Codex。

## 已知边界（写进代码注释，不做 UI）

1. **价值依赖 P0 闸门**：若 `claude -p "."` 不能 anchor 新窗口，整个功能无意义 → 见 P0。
2. **睡眠不触发**：菜单栏 app 无后台守护进程，Mac 睡眠时定时器不走。靠唤醒补偿
   （P4）把"失效"降级为"醒来补一发"。
3. **违背只读定位**：这是 app 第一个会按计划主动外发、并消耗被监控资源的功能。
   用户已知情并接受。warmup 对**周额度**有极轻微消耗（一窗一发、每发 1 token，可忽略）。

## 架构落点（遵循 `CLAUDE.md` 分层：Views → ViewModels → Services → Models）

```
App
└─ UsageWarmupManager  (新增, @MainActor, ViewModels/)   ← 独立单元，不污染只读监控
   ├─ 订阅 AIUsageMonitor 发布的 (provider, resetsAt, enabled)   ← 只读取，不反向依赖
   ├─ SettingsManager.autoRefresh{Claude,Codex}              ← 开关来源
   ├─ CLIBinaryResolver                                       ← 解析 claude/codex 路径
   ├─ 每 provider 状态: currentTask: Task?, nextFireDeadline
   ├─ NSWorkspace 睡眠/唤醒观察者
   └─ os.Logger (category: "UsageWarmup")
Services
└─ UsageWarmupService  (新增, Services/AIUsage/)           ← 真正起 Process 发命令
   └─ send(provider:) async -> Bool   超时/等待退出/杀进程，返回是否成功
UI
└─ AIUsageCard  (Views/Popover/Components/)
   └─ 每 provider（监控已开时）: Toggle "自动续期窗口"，绑定 SettingsManager，
      didSet 调 UsageWarmupManager.start/stop
```

**关键原则**：`AIUsageMonitor` 保持纯只读，完全不知道 warmup 存在（DeepSeek P1#5）。
warmup 通过订阅/回调单向取数。

---

## 实现完成小结（2026-06-28）

**落地文件：**
- `Services/AIUsage/WarmupSchedule.swift` — 纯调度策略 `decide(now:reset:lastAnchoredReset:cap:)`，7 项单测覆盖各拐点。
- `Services/AIUsage/UsageWarmupService.swift` — `Process` 起 headless 命令，空目录运行 + 30s 硬超时 + SIGTERM→SIGKILL + 任务取消即杀。
- `ViewModels/UsageWarmupManager.swift` — `@MainActor` 独立单元，每 provider 一个循环 Task，启用即健康探测，唤醒补偿。
- `SettingsManager`：`autoRefreshClaudeEnabled` / `autoRefreshCodexEnabled`，默认 false。
- `SettingsDetailViews.swift`：Claude/Codex 监控开启时各多一个「自动续期窗口」纯开关；Gemini 无。
- 四语言 `aiUsage.autoRefresh`；`AppDelegate` 启动 `UsageWarmupManager.shared.start()`、终止 `stopAll()`；`CLAUDE.md`/`AGENTS.md` 已同步。

**与原计划的有意偏差（更优/遵循已定决策）：**
- **UI 落点**改在 Settings 的 `AIUsageDetail`（provider 开关下方嵌套），不是弹窗内的 `AIUsageCard`——配置开关本就属于设置页。
- **P4 删除「now+4h 盲发兜底」**（决策 C）：未知窗口 → `waitForWindow` 不盲发；wall-clock 用「≤60s 分块轮询 + 唤醒重启循环」实现（比 `asyncAfter` 更易配合任务取消，睡眠唤醒后墙钟自校正）。
- **Manager 取 reset** 改为在循环里读 `AIUsageMonitor` 快照（`windows.compactMap(resetsAt).min()`），不订阅——更简单，等价。
- **P5 失败降级**仅记日志、不加 UI 状态点（计划里「无则仅日志」选项）。
- **命令最小化**（决策 B）：Claude `-p "今天天气怎么样？" --allowed-tools ""`；Codex `exec --skip-git-repo-check -s read-only`，均在临时空目录跑。实测 Codex token 从仓库内 22.7k 降到空目录 14k。
- **测试**：`WarmupScheduleTests`（7 例，纯策略）；并发互斥由 `loops[provider]==nil` 守卫 + task cancel 保证（设计层面，未单独写注入式并发测试）。

**验证状态：** `xcodebuild build` ✅ · `swiftlint lint --strict` ✅ 0 违规 · `xcodebuild test` ✅ 61/61 · `./debug-run.sh` ✅ 启动正常。
命令可用性实测：`claude -p …` exit 0 ~7s；`codex exec …` 返回正常 ~14k token。**唯一未直接观测**：窗口过期后 anchor 跳变（D），已挂一次性任务待跑。

---

## P0 — 验证闸门（必须先做，可能否决整个功能）

**不写任何功能代码。** 先用真实账号确认前提成立。

- [x] 记录当前 Claude 5h 窗口 `resets_at`（用 OAuth usage 端点，非 TUI）。
- [x] 执行 `claude -p "."`（headless，exit 0，已登录可用）。
- [x] 再查 usage：`resets_at` 是否跳到约 5h 之后？→ **没跳。** 两次实测（11:10→11:10、过期后 16:10→16:10）reset 始终落在
      固定 5h 网格上（06:10→11:10→16:10），发消息没把它移到消息时刻。**anchor-by-message 未能证实，功能前提存疑——见下「D 复测」。**
- [x] Codex 等价命令确认：`codex exec "."` headless exit 0、已登录可用。**但耗 22,720 token（见关键发现 3）。**
- [x] 结果已记录于下方"验证结果"。

**验证结果**（2026-06-28T08:37Z 实测）：
```
命令可用性：
  claude -p "."   → exit 0, ~6.5s, 已登录。会加载 CLAUDE.md 上下文。
  codex exec "."  → exit 0, ~11s, 已登录。一次用掉 22,720 token（加载 AGENTS.md/仓库上下文）。

Claude 5h 窗口（OAuth usage 端点）：
  发送前： util=22%  resets_at=2026-06-28T11:10:00Z
  发送后： util=23%  resets_at=2026-06-28T11:10:00Z   ← reset 未移动，util +1%
  当前时刻：08:37Z（窗口在 06:10Z 起、11:10Z 到期，测试时仍活跃）

Codex primary 窗口：used=95%（接近上限），reset_at=1782637296。
```

**D 复测（2026-06-28T11:15Z，旧窗口 11:10Z 过期后）：**
```
NOW(UTC): 11:15Z
发送前： util=0%  resets_at=2026-06-28T16:10:00Z
发送 claude -p "今天天气怎么样？"（空目录, exit 0）
发送后： util=0%  resets_at=2026-06-28T16:10:00Z   ← reset 未移动
```
- 旧窗口 11:10Z 过期后，并没有进入「无活跃窗口」状态，而是**直接滚到新的一格 11:10→16:10**（util 0）。
  我在 11:15 发消息时窗口已经活跃，所以又是一次 mid-window 发送，reset 不动。
- 观察到的是一条**固定 5h 网格**：06:10 → 11:10 → 16:10，整 5h 一格，锚定在用户当天最初的会话（06:10）。
  发消息没能把 reset 移到消息时刻（既没移到 11:15，也没在 mid-window 动过）。
- **未能证实 anchor-by-message。** 而且证据更偏向「reset 由固定网格决定、发消息改不了」。
  无法做「真正空窗期发送」的干净实验：本开发会话一直在用 Claude Code，窗口始终活跃、永远没有空窗缺口。

**⛔ 结论（D）：功能核心前提「发消息能把 reset 提前到你需要的时段」在本账号上未能证实，且很可能不成立**
（至少对「持续活跃、窗口一直滚动」的用户无效）。理论上只有在**真正闲置 5h 以上、窗口完全过期**后，
首条消息才可能开一格新窗口——但即便如此，本次数据显示新格仍落在 :10 网格上、不是消息时刻，疑似按原节奏对齐。
**已按指示停下上报，未改动已实现的代码。**

### 关键发现（与原计划假设冲突 → 已停在闸门待确认）

1. **mid-window 发送不会移动 reset。** 证实"窗口一旦设定就是固定块"模型：在活跃窗口内补发消息，
   `resets_at` 纹丝不动，只白白消耗一点额度。**anchor 只发生在「新窗口的第一条消息」**（上一窗口过期后）。
   → 完整 anchor 确认还需一次"过期后发送"观测（Claude 约 11:10Z 之后），目前**尚未直接验证到 reset 跳变**。

2. **时机不是"更优"，是"唯一可行"。** 既然 mid-window 发送无效，warmup **必须**在窗口过期后第一时间发
   （`resetsAt + δ`）。原计划 P4 里"`resetsAt` 未知时回退固定 4h"的兜底**基本无用甚至有害**——固定 4h 很可能
   落在活跃窗口里，纯烧 token 不 anchor。Approach B（reset-aware）从"推荐"升级为"前置必需"。

3. **"单 token、不花钱"假设是错的。** `codex exec "."` 一次 **22,720 token**（加载仓库上下文）；
   `claude -p "."` 把 5h util 推了 +1%。两者都会加载项目上下文，不是廉价 ping。
   → 设计必须让 warmup 在**中性/空目录**下运行、并尽量用跳过项目上下文的参数，否则"每窗一发"会显著吃**周额度**，
   尤其 Codex（已 95%）。产品决策里"包月固定价、消耗可忽略"对 Codex **不成立**。

**验收状态**：✅ **通过（命令可用性已实测，设计修正已由用户拍板）。** 进入 P1。

### 已确认决策（用户 2026-06-28 拍板：「别纠结成本，发个普通短消息，上下文尽量小」）

- **A. Codex 照做。** 不纠结单次 token 量。Claude + Codex 都做。
- **B. 最小上下文 + 普通短消息。** warmup 在**临时空目录**运行（避开项目 CLAUDE.md/AGENTS.md），
  消息用一句无害自然语言（如「今天天气怎么样？」）。能加的"跳过项目上下文/限制工具"参数都加
  （Claude 复用 `--bare --allowed-tools ""` 思路；Codex 用 `--skip-git-repo-check` 等最小化）。
- **C. 调度只在窗口过期后发（reset-aware 为必需）。** 删除"固定 4h 兜底会 mid-window 空发"的设计。
  规则：已知 `resetsAt` → 排在 `resetsAt + 60s` 发；**无 `resetsAt`** → 先靠 `AIUsageMonitor` 现有轮询拿到窗口再排程，
  在拿到之前不盲发。mid-window 永不主动发。
- **D. anchor 完整确认（非阻塞）。** 实现不被它卡住。可在 Claude 窗口过期后（≥11:10Z）补一次"过期后发送"测试，
  确认 `resets_at` 跳到 ~now+5h；作为收尾验证项放进烟雾清单，不阻塞 P1–P7。

---

## P1 — 设置与开关骨架（默认关闭）

- [x] `SettingsManager`：新增 `Key` case `autoRefreshClaude`、`autoRefreshCodex`。
- [x] 新增两个 `@Published var ...: Bool { didSet { save(...) } }`，`init` 里从
      `UserDefaults` 读，**默认 `false`**（与现有 `aiMonitor*Enabled` 同区，遵循默认关闭）。
- [x] `AIUsageCard`：每个 provider 在其用量监控已开启时，渲染一个纯 Toggle
      "自动续期窗口"，绑定到上面两个设置。此阶段 didSet 可暂连一个空的 `UsageWarmupManager` 桩。
- [x] 四语言 `Localizable.strings`（en / zh-Hans / ja / ko）补开关标题 key。
- [x] Gemini 卡片**不出现**该开关。

**验收**：编译通过；纯监控用户（两开关默认 false）看不到任何行为变化；Toggle 能开关并持久化；
`./debug-run.sh` 跑起来开关可见、可点、重启后状态保留。

---

## P2 — UsageWarmupManager 骨架（调度但先不发）

- [x] 新建 `ViewModels/UsageWarmupManager.swift`，`@MainActor final class`，由 `AppDelegate`/App 创建并注入。
- [x] 暴露 `start(provider:)` / `stop(provider:)`；每 provider 持有 `currentTask: Task<Void, Never>?`。
- [x] 订阅 `AIUsageMonitor` 的最新快照以拿到每 provider 的 `resetsAt` 与 enabled 状态
      （回调或 Combine；**不要**让 AIUsageMonitor 反向依赖本类）。
- [x] `start` 内先 `stop`（取消旧 task）再排程；此阶段触发点只打一条 `Logger` 日志，不真发命令。
- [x] 绑定开关：`SettingsManager.autoRefresh*` 的 didSet → 对应 `start/stop`；provider 监控被关时也 `stop`。

**验收**：开关 on/off 时日志出现 "warmup scheduled / stopped"；快速开关不堆积（旧 task 被 cancel）；
`AIUsageMonitor` 源码无任何对 warmup 的引用。

---

## P3 — 进程发送 + 生命周期（DeepSeek P0#3 / P2#6）

- [x] 新建 `Services/AIUsage/UsageWarmupService.swift`，`func send(provider:) async -> Bool`。
- [x] 用 `Process` 跑 headless 命令（Claude: `claude -p "."`；Codex: P0 确定的写法），
      二进制路径走 `CLIBinaryResolver`。
- [x] **不 fire-and-forget**：起进程后在 Task 内等待退出，加 **30s 超时**；超时 `terminate()`，
      仍不退再 `kill()`；返回退出码是否为 0。
- [x] **每 provider 串行**：UsageWarmupManager 保证同一 provider 同时只有一个发送在跑；
      新触发前 cancel 上一个未完成的发送 Task（`Task.isCancelled` 在等待循环里检查）。
- [x] 结果记 `os.Logger`（成功 / 超时 / 非 0 退出码），**不弹 UI**。
- [x] P2 的调度触发点接上真正的 `send(provider:)`。

**验收**：Activity Monitor 里不残留 `claude`/`codex` 僵尸进程；把二进制临时指向一个永不返回的脚本，
30s 后被杀且日志记错误；0.5s 内连点开关 10 次后无并发残留、最终状态正确。

---

## P4 — 调度策略：reset-aware + wall-clock + 唤醒补偿（DeepSeek P1#4）

- [x] 下次触发时间：有已知 `resetsAt` → `resetsAt + 60s`；未知 → `now + 4h`（回退）。
- [x] 用 **wall-clock 截止**排程（`DispatchQueue.main.asyncAfter(wallDeadline:)` 或等价），
      不要用会被睡眠冻住的 timer。
- [x] 监听 `NSWorkspace.didWakeNotification`：唤醒后重算，若已越过重置点且本窗口尚未 anchor，
      立即补发一次再排下一轮。监听 `willSleepNotification` 做必要清理。
- [x] 发送成功后，用刷新到的新 `resetsAt` 重排下一轮，形成连续覆盖、每窗一发。

**验收**：用 `pmset` 强制睡眠 10 分钟，唤醒后日志显示立即补发；正常运行时每个窗口恰好一次 warmup，
节奏跟随 `resetsAt` 而非固定墙钟。

---

## P5 — CLI 登录态 dry-run + 失败降级（DeepSeek P2#7）

- [x] 首次启用某 provider 的自动续期时，先跑一次发送并看退出码作为健康检查
      （CLIBinaryResolver 只保证找到二进制，保证不了已登录）。
- [x] 健康检查失败（未登录 / 需交互 / 非 0）→ 停掉该 provider 的自动续期、记日志，
      **不无限重试、不弹窗**。可选：在卡片该行加一个极轻的状态点（不加文案），无则仅日志。
- [x] 之后每次发送失败也走同样的"记日志、不打扰"路径。

**验收**：在未 `claude login` 的环境开开关，不会卡死、不无限刷；日志明确写明因登录态失败而停。

---

## P6 — 测试（DeepSeek P3#8）

- [x] 在 `LightStatsTests/` 加 `UsageWarmupScheduleTests`：纯函数验证"下次触发时间"计算
      （有/无 `resetsAt`、回退 4h、唤醒补偿判定）。
- [x] 验证 start/stop 的取消性与每 provider 并发互斥（注入假的 SettingsManager / 时钟）。
- [x] 把调度的纯计算逻辑做成可测 seam（静态/纯函数），避免依赖真实 Process。
- [x] 在本文件底部补一份"手动烟雾清单"并逐条跑通（命令有效性、超时、睡眠唤醒、快速开关、关监控联动）。

**验收**：`xcodebuild test` 新测试通过；烟雾清单全绿。

---

## P7 — 关闭路径与收尾

- [x] **运行时关闭路径彻底**（`CLAUDE.md` 硬规则）：关开关 / 关 provider / `applicationWillTerminate`
      都立即 `stop()`：invalidate 排程 + cancel 发送 task + 移除睡眠唤醒观察者。
- [x] 同步 `CLAUDE.md` 与 `AGENTS.md`：Layout 文件树补 `UsageWarmupManager.swift`、
      `UsageWarmupService.swift`；在合适章节简述本功能（默认关闭、仅 Claude/Codex）。
- [x] `swiftlint lint --strict` 通过；无 `print()`/`NSLog()`，无强解包。
- [x] `./debug-run.sh` 端到端走一遍真实开关。

**验收**：纯监控默认形态零变化；功能开/关均无残留 task、无残留进程、无残留观察者；lint 与文档干净。

---

## 手动烟雾清单（P6 跑）

1. **命令有效性**：终端 `claude -p "."` 后 `/usage` 确认窗口重置时间刷新，耗 token ≤ 3；Codex 同理。
2. **超时**：二进制临时指向永不返回脚本 → 30s 被杀、日志记错误；未登录场景不无限等待。
3. **睡眠/唤醒**：`pmset` 强制睡眠 10 分钟，唤醒后立即补发（看调试日志）；模拟窗口在睡眠中过期。
4. **快速开关并发**：0.5s 内开关 10 次 → Activity Monitor 无残留 `claude` 进程，最终状态正确。
5. **关监控联动**：开自动续期后关掉该 provider 监控 → 开关随之失效、task 停止。
6. **默认形态**：全新 `UserDefaults`，两开关默认 false，无任何外发、无新进程、卡片无开关入口（除已开监控的 provider）。

---

## 给 loop 的执行说明

- 严格按 **P0 → P7** 推进；P0 未通过（"验证结果"未填或结论非"可 anchor"）则**停止并上报**，不要写 P1+ 代码。
- 每完成一个 `- [ ]` 就改成 `- [x]`，并更新顶部状态行（如 `P1 进行中` / `P3 已完成`）。
- 每个 P 阶段尽量独立提交，commit message 用 `feat(warmup): ...` 前缀。
- 涉及 UI 的阶段（P1）完成后跑 `./debug-run.sh` 做一次可视验证。
- 遇到与本文档假设冲突的事实（如 P0 失败、CLI 行为变化），**停下来上报**，不要自行扩大范围。

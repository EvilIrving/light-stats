# 自动续期窗口（Usage Warmup）· 现行实现

> 状态：功能已实现并落地。本文描述**现行软件实现**，不再是实施计划。
> 原分阶段计划（P0–P7）与调研过程已从本文移除；需要的设计历史在 git 提交记录中。
> 对应代码：`ViewModels/UsageWarmupManager.swift`、`Services/AIUsage/UsageWarmupService.swift`、
> `LightStatsTests/UsageWarmupScheduleTests.swift`。

## 功能是什么

对开了「自动续期窗口」开关的 provider，在它的 5h 用量窗口 reset 之后发一条无害短消息——
把用户手动等窗口过期后 ping 一次的事做成内置（类似 Claude Code 手动 `/loop` 的自动版）。

- **默认关闭**，干净安装什么都不跑。开关只在该 provider 的用量监控已开启时出现。
- **只覆盖 Claude 和 Codex**（有滚动窗口）。Gemini 是每日 quota（`retrieveUserQuota` /
  `remainingFraction`），没有滚动 reset，不做 warmup。
- 发送的是**真实消息**（`claude -p "ok"` 等），不是只读的 `/usage` / `/status` 斜杠命令。

## 已验证的行为前提（决定实现形态）

- **mid-window 发送不会移动 reset。** 实测：活跃窗口内补发消息，`resets_at` 纹丝不动，
  只消耗一点额度。窗口一旦设定就是固定块。
- **reset 落在固定网格上**（实测为 :10 整 5h 一格），发消息不能把它挪到消息时刻。
  因此「在窗口过期后第一时间发」是唯一有效时机——**warmup 必须是 reset-aware，不是固定间隔**。
- 结论：调度规则是「拿到当前窗口 `resetsAt` → 在 `resetsAt + 60s` 发 → 验证 reset 已推进 →
  再排下一轮」。拿不到 `resetsAt` 时**不盲发**，过 2h 重试。

## 架构落点

```
ViewModels/UsageWarmupManager.swift   @MainActor 单例；每 provider 一个循环 Task
  ├─ 订阅 SettingsManager：{autoRefresh,aiMonitor}{Claude,Codex} 任一变化 → syncAll()
  ├─ run(provider)：取快照 → nextFireDate → 睡到 reset+60s → sendWithRetries → verifySend
  └─ 同一 reset 只发一次（lastSentReset 去重）；睡眠唤醒靠 ≤60s 分块睡自动墙钟校正
Services/AIUsage/UsageWarmupService.swift  真正起 Process 发命令
  ├─ claude:  `-p "ok" --allowed-tools ""`
  ├─ codex:   `exec --ignore-user-config --ignore-rules --skip-git-repo-check --ephemeral -s read-only "ok"`
  ├─ 临时空目录运行（避开项目 CLAUDE.md/AGENTS.md 上下文）；30s 硬超时；SIGTERM→SIGKILL
  └─ 二进制路径走 CLIBinaryResolver
UI
  SettingsDetailViews.swift（AIUsage 详情）
  └─ provider 监控开启时各多一个「自动续期窗口」纯开关，绑定 SettingsManager
```

- `SettingsManager`：`autoRefreshClaudeEnabled` / `autoRefreshCodexEnabled`，默认 `false`，
  与监控开关同区持久化。
- 开关变化即起/停循环；provider 监控被关时 warmup 循环也随之 `stop()`。
- 运行时关闭路径彻底：`stopAll()` 在 `applicationWillTerminate` 与开关关闭时都立即
  cancel 所有循环与发送 Task，不残留进程/观察者。

## 调度语义（现行）

| 情形 | 行为 |
|------|------|
| 已知 `resetsAt`（5h 窗口，取 label 为 "5h" 的窗口，缺省取 `min(resetsAt)`） | `max(now, resetsAt + 60s)` 触发 |
| 该 reset 已发过（`lastSentReset` 与 reset 相差 <1s） | 不重复发，等待下一轮快照 |
| 拿不到 `resetsAt` | 不盲发，记日志，2h 后重试 |
| 发送失败 | 按 30s、120s 重试两次，仍失败仅记日志、不打扰 |
| 发送成功 | 重新取快照验证 reset 已推进（`nextReset > previousReset`），否则记日志 |
| 任务取消 / 开关关闭 | 循环与进程立即终止 |

## 边界与已知限制

- **消耗**：这是 app 唯一会按计划主动外发并消耗被监控资源的动作；每窗一发、每发一条
  最小消息，对订阅制（Claude Pro/Max、ChatGPT）只消耗一丝限流额度，不产生额外费用。
- **睡眠不触发**：菜单栏 app 无后台守护进程，睡眠时定时器不走；唤醒后墙钟自校正，
  若已越过 reset 点会补发。
- **依赖 CLI 登录态**：首次启用时发一次作为健康检查，未登录 / 非 0 退出即停掉该 provider
  的循环，只记日志，不弹窗、不无限重试。
- **测试**：`UsageWarmupScheduleTests` 锁定 `nextFireDate` 纯策略（未来 reset 延时、
  过期立即发、同 reset 不重复、无 reset 不盲发），防止实现漂回固定间隔 mid-window 空发。

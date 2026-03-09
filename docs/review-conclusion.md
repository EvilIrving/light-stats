# Code Review 结论（按优先级重分级）

对先前 15 条问题的复核结论，按 **Critical / Medium / Nice-to-have** 重新分级，并标注每条在代码中的核实结果。

---

## Critical（必须处理）

| # | 原描述 | 核实结论 | 建议 |
|---|--------|----------|------|
| 3 | Debug 代码留在生产路径：`SMCInfo.debugSMC()` 在 AppDelegate 启动时无条件调用 | **成立** | **已修复**：已从 `startMonitoring()` 中移除该调用。 |

当前无其他列为 Critical 的条目。原清单中的 #1、#2、#4、#5 经代码核对后归入 Medium 或驳回，见下。

---

## Medium（建议尽快处理）

| # | 原描述 | 核实结论 | 建议 |
|---|--------|----------|------|
| 1 | SystemMonitor / CPUInfo / NetworkInfo 存在线程安全问题（`@unchecked Sendable` 且无同步） | **部分成立** | `CPUInfo`、`NetworkInfo` 确有可变状态 + `@unchecked Sendable`，属潜在风险；当前仅在 `@MainActor` 的 SystemMonitor 中调用，未见实际跨线程竞态。建议：若未来在后台线程使用，改为加锁或去掉 Sendable 并保证单线程访问。 |
| 5 | 网络统计与设置管理存在 race conditions | **部分成立** | `NetworkInfo` 内部有 `previousBytes`/`previousTime` 可变状态，若多线程调用会有竞态；SettingsManager 为 `@MainActor`，未见明显数据竞争。建议：保持 NetworkInfo 仅由 MainActor 调用，或为其状态加锁。 |
| 6 | 系统 API 调用缺少错误处理 | **成立** | 多处 Mach/IOKit/getifaddrs 失败时仅返回 nil/空，无统一错误路径或日志。建议：对关键路径增加 `os_log` 或结构化错误返回，便于排查。 |
| 9 | 关键功能缺少单元测试 | **成立** | 仓库内无 `Tests` 目录或 XCTest 用例。建议：至少为 ProcessService.parseTopOutput、SMCInfo 键解析、NetworkInfo 统计等核心逻辑补测。 |
| 11 | IOKit 调用无错误日志 | **成立** | `SMCInfo.open()`/`readKey()` 等失败时只返回 false/nil，未打日志。建议：失败时用 `os_log(.error, ...)` 记录返回值或错误码。 |

---

## Nice-to-have（可逐步改进）

| # | 原描述 | 核实结论 | 建议 |
|---|--------|----------|------|
| 2 | Timer 与 Combine 订阅未正确清理，存在内存泄漏风险 | **程度偏重** | Timer 在 `stopMonitoring()` 中已 `invalidate()`，闭包使用 `[weak self]`；AppDelegate 的 `cancellables` 与进程同生命周期。建议：若存在多次创建 AppDelegate/Monitor 的场景，再显式 cancel 订阅。 |
| 4 | ProcessService.parseTopOutput() 存在 unsafe force unwrap | **不成立** | 该函数内无 `!` 强制解包，使用 `guard let`、`components.last ?? "0"` 等安全写法。无需修改。 |
| 7 | 与具体实现耦合过紧 | **部分成立** | 已有 `ProcessServiceProtocol` 注入（如 AppMemoryManager），并非全盘耦合。建议：需要替换实现或做测试 double 时再进一步抽象。 |
| 8 | 嵌套 Publisher 链过复杂 | **成立** | AppDelegate 中 `Publishers.CombineLatest4` + `combineLatest` + `CombineLatest3` 可读性差。建议：抽成 `statusBarPublisher` 等命名组合，或改用 `@Published` 驱动单一派生值。 |
| 10 | 未处理网络接口变化 | **部分成立** | 每次通过 `getifaddrs` 重新遍历，接口增删会反映在当次统计；若接口或计数器回绕，会短暂显示 0。建议：文档说明或对“计数器回绕”做一次兼容处理即可。 |

---

## 汇总

- **Critical**：1 条，已修复（移除生产路径中的 `SMCInfo.debugSMC()`）。
- **Medium**：5 条，建议在后续迭代中处理（线程安全约定、错误处理与日志、单元测试）。
- **Nice-to-have**：5 条，多为可读性、可维护性与边界情况；#4 已核实为误报。

如需把某条从 Medium 提升为 Critical（例如上线前必须修），可按团队策略再调优先级。

# Light Stats v2 路线图与交接总纲

> 本目录是 Light Stats 大版本（v2）的纲领文档。每个阶段（Phase）是一份**可独立执行 + 可交接**的文档：
> 一个全新的会话（cold start）读完对应阶段文档即可开工；做完后在该文档底部的「交接记录」里写清结果。
> 下一个阶段开工前，先读上一阶段的「交接记录」复盘。

---

## 0. 背景与目标

Light Stats 现状：菜单栏监控 CPU / GPU / 内存 / 磁盘占用 / 网络速率 / 温度 / 风扇 / 进程，外加内存清理。

v2 的核心诉求（来自项目作者）：
1. **网络层做深**——不仅看上下行速率，还要知道「当前是不是处在代理环境、走的是哪个出口节点」。这是两个参考项目（Mole、RunCat365）都没做到的差异化点。
2. 补齐缺失的硬数据——电池/功耗、磁盘 IO、外置盘。
3. 给一个「整体健康度」门面，把零散指标收敛成一个总分。

### 参考项目结论（已调研）

- **RunCat365**（C# / .NET 9）：**Windows 专属**，本质是任务栏跑猫动画顺带显示统计。网络方面零产出，**与本次诉求无关**。仅工程分层（每指标一个 Repository）思路可参考，无新意。
- **Mole**（Go / `mo status`）：真正的参考对象。CPU/GPU/内存/磁盘/磁盘IO/网络/代理/电池/温度/进程/蓝牙/硬件/健康分。
  - **关键认知**：Mole 的代理检测 `collectProxy()` 只是**本地配置探测**（`scutil --proxy` + 环境变量 + 活跃 utun 接口），拿到的 IP 是**内网网卡 IP**。它能回答「系统配了代理没有」，**回答不了「出口是谁、在哪个节点」**。出口探测是我们要补的差异化能力。
  - 详细技术拆解见 [`../mole_analysis.md`](../mole_analysis.md)。

---

## 1. 阶段划分

| 阶段 | 主题 | 差异化价值 | 风险 | 文档 |
|------|------|-----------|------|------|
| Phase 1 | 网络 / 代理 / 出口节点 | 高（独有） | 中（含外发请求，已设默认关闭兜底） | [`phase-1-network-proxy.md`](phase-1-network-proxy.md) |
| Phase 2 | 电池/功耗 + 磁盘 IO/外置盘 | 中（补齐空白） | 低（纯本地原生 API） | [`phase-2-battery-disk-io.md`](phase-2-battery-disk-io.md) |
| Phase 3 | 健康评分门面 | 中（收敛体验） | 低（依赖前两期数据） | [`phase-3-health-score.md`](phase-3-health-score.md) |

执行顺序固定 **1 → 2 → 3**。Phase 3 依赖 1/2 产出的数据，必须最后做。

---

## 2. 关键设计决策（已与作者确认）

- **出口 IP / 节点探测**：会请求外部 geo-IP 服务（ip.sb / ip-api.com / ipinfo.io）。
  **态度：功能内置，但默认关闭**。需用户在设置里主动开启，首次开启弹隐私说明。详见 Phase 1。
- **优先 Swift 原生 API，不 fork 命令**：比 Mole 的 shell-out 更稳、更省电、沙盒更友好。
  - 系统代理：`CFNetworkCopySystemProxySettings()`（替代 `scutil --proxy`）
  - 网络路径/默认路由：`NWPathMonitor`
  - 电池/电源：`IOPSCopyPowerSourcesInfo` + `AppleSmartBattery`（IOKit，替代 `pmset`/`ioreg`）
  - 外置盘：`DiskArbitration`（替代 `diskutil info`）
  - 出口探测：`URLSession`
- **分层缓存**（借 Mole）：硬件信息 10min / 电池健康 30s / 出口 IP 30–60s / 实时指标按刷新率。
  出口探测**必须**缓存，绝不能每个刷新周期都打外部 API。
- **并发采集**：用 `async let` / TaskGroup 并行各采集器（现有 `MonitorSampler` 已局部用 `async let topProcesses`，逐步推广）。

---

## 3. 代码现状速查（执行阶段前必读）

实际项目根目录：`Light Stats/`（注意目录名含空格）。

- 全局常量：[`Light Stats/ViewModels/SettingsManager.swift`](../../Light Stats/ViewModels/SettingsManager.swift) 顶部 `enum AppConfig`。
- 设置：同文件 `SettingsManaging` 协议 + `SettingsManager`（单例 `SettingsManager.shared`）。
  - 新增设置项的标准做法：协议加属性 → `@Published`（`didSet { save(...) }`）→ `Key` 枚举加 case → `init()` 读默认值。
- 采集编排：[`Light Stats/ViewModels/SystemMonitor.swift`](../../Light Stats/ViewModels/SystemMonitor.swift)
  - `private struct SystemSnapshot`：一次采集的全部字段，新增数据加这里。
  - `private actor MonitorSampler`：实际采集，懒加载各 Info/Service 对象。
  - `SystemMonitor`（`ObservableObject`）：`@Published` 字段供视图绑定。
- 数据模型：[`Light Stats/Models/`](../../Light Stats/Models/)（`CPUInfo`、`MemoryInfo`、`DiskInfo`、`GPUInfo`、`NetworkInfo` 等）。
- 系统服务：[`Light Stats/Services/`](../../Light Stats/Services/)（`SMCInfo`、`ProcessService`）。
- 视图：
  - 菜单栏：[`Light Stats/Views/StatusBar/StatusBarView.swift`](../../Light Stats/Views/StatusBar/)
  - 浮窗概览（网络卡片在这）：[`Light Stats/Views/Popover/OverviewTabView.swift`](../../Light Stats/Views/Popover/OverviewTabView.swift)
  - 设置：[`Light Stats/Views/Settings/SettingsView.swift`](../../Light Stats/Views/Settings/)
  - 复用卡片：`Views/Popover/Components/BentoCard.swift`
- 三语本地化：`Light Stats/Resources/{en,zh-Hans,ja}.lproj/Localizable.strings`，用法 `"key".localized`。**每加一个用户可见字符串，三个文件都要补 key。**
- 沙盒权限：[`Light Stats/LightStats.entitlements`](../../Light Stats/LightStats.entitlements)。**Phase 1 出口探测需要 `com.apple.security.network.client`，开工时先确认。**
- 现有网络实现（最薄弱）：[`Light Stats/Models/NetworkInfo.swift`](../../Light Stats/Models/NetworkInfo.swift)——只有 `getifaddrs` 算上下行速率，**无 IP、无代理、无出口**。

### Xcode 工程注意
新增的 `.swift` 文件必须加进 `Light Stats.xcodeproj` 的 build target，否则不参与编译。用 Xcode 添加，或确认 `project.pbxproj` 已登记。每个阶段结束都要能 `Build Succeeded`。

---

## 4. 交接流程（每个阶段都遵守）

1. **开工**：执行者读本 README + 对应阶段文档 + 上一阶段的「交接记录」。
2. **执行**：按阶段文档的任务清单做，逐项勾掉。遇到偏离/取舍，记在脑子里，最后写进交接记录。
3. **验收**：跑通阶段文档的「验收标准」（编译通过 + 手测要点）。
4. **写交接**：在**该阶段文档底部**的「## 交接记录 (Handoff)」里填：
   - 完成日期 / 实际改动的文件清单
   - 与计划的偏差及原因
   - 已知问题 / 遗留 TODO
   - 给下一阶段的提醒（接口约定、命名、坑）
5. **复盘**：作者读交接记录，确认后再开下一阶段的新会话。

> 交接记录模板见每个阶段文档末尾，已预置空表格，直接填即可。

---

## 5. 当前进度

| 阶段 | 状态 |
|------|------|
| 文档总纲 | ✅ 完成 |
| Phase 1 | ✅ 完成（2026-06-06，编译通过；交互式手测待作者验收） |
| Phase 2 | ✅ 完成（2026-06-07，编译通过 + 启动冒烟无崩溃；交互式手测待作者验收） |
| Phase 3 | ⬜ 未开始 |

> 每完成一个阶段，执行者把对应行改为 ✅ 并附完成日期。

# Light Stats 演进计划

> 状态：进行中 · 最后更新 2026-06-26 · **P1、P2、P3、P4 已完成**
>
> 本文是一份分阶段的工程计划，覆盖四条工作线：**产品定位与"默认关闭"原则**、
> **文档同步**、**测试补充**、**AI 用量服务抽象**。每个阶段尽量独立可交付、可单独提 PR。

## 背景与目标

Light Stats 最初定位是"克制、不越界"的菜单栏监控仪表（见 `PRODUCT.md`）。
随着自用需求增长，它已经长成一个替代多款小工具的集合：在监控之外又加入了
窗口管理（`WindowSnappingService` / `MagnetHotKeyService` / `TitlebarGestureService`）、
滚动方向反转（`ScrollDirectionService`）、键盘清洁锁（`KeyboardLockService`）、
三家 AI CLI 用量监控等。

**新的产品边界（本计划的前提）：**

- 承认产品已成长为"轻量系统工具箱"，不再假装只是只读监控器。
- 但**继续坚持"克制、不越界"**：所有监控之外的能力（窗口管理、滚动反转、AI 用量、
  出口节点探测）**默认全部关闭**。不使用的用户不会看到入口、不被请求权限、不产生
  任何采集或事件 tap 开销。
- **轻量是硬约束**：常驻内存目标维持在 ~50MB 量级；默认形态（仅监控）不得启动任何
  `CGEventTap`、不请求辅助功能权限、不发起任何网络请求（自动更新检查除外，且可关）。

现状盘点（已核对源码）：

- 默认值**已基本正确**：`exitNodeDetectionEnabled`、`aiMonitor{Claude,Codex,Gemini}Enabled`、
  `scrollReverseEnabled`、`magnetHotKeysEnabled`、`titlebarGesturesEnabled` 均默认 `false`
  （`SettingsManager.swift:382-399`）。
- event tap **已经懒加载**：`syncScrollService` / `syncWindowControlServices` 仅在开启时
  创建 tap（`AppDelegate.swift:537-560`）；`AIUsageMonitor` 在 `enabledProviders` 为空时
  不轮询（`AIUsageMonitor.swift:124-136`）。
- **已知缺口**：窗口控制的菜单栏图标 `setupWindowControlsStatusItem()` 在
  `AppDelegate.swift:77` **无条件创建**——纯监控用户也会看到窗口控制图标。这是
  "默认关闭"原则的主要漏网点，需要总开关。
- **文档已漂移**：`CLAUDE.md` / `AGENTS.md` 的文件树缺失十余个实际文件；其
  "Lint thresholds" 表与 `.swiftlint.yml` 实际阈值严重不符。
- **测试几乎为零，且未接入工程**：仅 `LightStatsTests/LightStatsSmokeTests.swift`（103 行），
  但 `Light Stats.xcodeproj/project.pbxproj` 里**没有 unit-test-bundle target、没有带测试
  动作的 scheme**——该文件只是躺在磁盘上，`xcodebuild test` 实际跑不到它（README 的相关
  说法已失效）。最该被测的纯函数 `HealthScoreService` 和脆弱的 AI 解析逻辑都没有任何回归保护。

> 说明：以上"测试 target 未接入"、lint 阈值不符、`unowned_guard` 为无效规则等事实，
> 已由第二方（Codex）只读评审独立核对确认。

---

## 阶段总览

| 阶段 | 主题 | 类型 | 风险 | 依赖 | 状态 |
|------|------|------|------|------|------|
| P1 | 产品边界 + "默认关闭"巩固 | 代码（小）+ 文档 | 低 | — | ✅ 已完成 |
| P2 | 文档同步（CLAUDE/AGENTS/PRODUCT） | 纯文档 | 极低 | P1 决策 | ✅ 已完成 |
| P3 | 测试地基（HealthScore + 默认值 + AI fixture） | 纯新增测试 | 低 | — | ✅ 已完成 |
| P4 | AI 用量服务抽象重构 | 代码（中） | 中 | P3 | ✅ 已完成 |
| P5 | 模块化收尾 + 轻量回归验证 | 代码（小）+ 验证 | 低 | P1, P4 |

建议顺序：**P3 与 P1/P2 可并行**（测试是纯新增，不阻塞任何人）。**P4 必须在 P3 之后**
（先有安全网再重构）。P5 收尾。

---

## P1 · 产品边界与"默认关闭"巩固 ✅ 已完成（2026-06-26）

**目标**：让"不使用附加功能的用户感受不到附加功能的存在"成为代码层面的事实，而不只是
默认值。

> **完成记录**：窗口管理收敛为单一总开关 `windowManagementEnabled`（默认关，**不迁移**老用户，
> 经用户确认）；菜单栏图标改为懒创建/移除，纯监控用户不再看到 `rectangle.split.2x1`；
> 删除 `magnetHotKeysEnabled` / `titlebarGesturesEnabled` 两个子开关及菜单内 toggle；
> 设置页分为「监控（核心）」「附加工具（默认关闭）」两组；四语言文案同步；冷启动检查单
> 已沉淀进 `CLAUDE.md` / `AGENTS.md` 的「Default form (zero-intrusion)」段。任务 3（权限时机）
> 核对后确认现状已满足，无需改动。`swiftlint --strict` 0 违规、构建通过、本地化校验通过。

### 任务

1. **窗口控制总开关（单一开关，开即可用）**。新增 `windowManagementEnabled`（默认 `false`）
   作为**唯一总开关**，遵循"可见性 = 功能启动 = 快捷键启用"的原则：
   - 开关打开 → 菜单栏图标出现 **且** 全局快捷键生效 **且** 标题栏手势生效，立即可用；
     开关关闭 → 三者一起消失、tap 全部 stop。用户不需要理解"图标"与"按键"是分开的两件事。
   - 这是对此前评审中"把可见性与快捷键拆成两个开关"建议的**有意覆盖**：单开关对用户更友好，
     避免"图标在那却没反应"的困惑。
   - 现有 `magnetHotKeysEnabled` / `titlebarGesturesEnabled` 收敛到该总开关之下：
     要么直接由总开关统一驱动，要么作为"已开启窗口管理"后才显示的**次级细调**（如允许单独
     关掉触控板手势以防误触），但总开关本身必须自足——只开总开关就能用核心快捷键。
   - 改 `AppDelegate.setupWindowControlsStatusItem()`：仅当开关开启时才创建
     `windowControlsStatusItem`；关闭时移除 status item。
   - 订阅该开关变化，动态增删菜单栏图标（参照 `magnetHotKeysEnabled` 的 `sink` 模式，
     `AppDelegate.swift:97-111`）。
   - 验收：全新安装、不动任何设置时，菜单栏**只有监控项**，没有 `rectangle.split.2x1` 图标。

2. **默认形态零侵入审计**。写一份"冷启动检查单"并逐项核对：
   - 默认配置下不调用 `AXIsProcessTrustedWithOptions` / 不弹辅助功能授权框。
   - 默认配置下无任何 `CGEventTap` 被创建（scroll / keyboard / titlebar 全关）。
   - 默认配置下除 `autoCheckUpdates`（可关）外无出站网络请求。
   - 验收：用 Console / Activity Monitor 确认空闲常驻内存 ~50MB，无 event tap 线程。

3. **权限请求时机收敛**。确保辅助功能权限**只在用户主动开启某个需要它的功能时**才请求
   （现有 `startScrollServiceOrPrompt` / `startMagnetHotKeysOrPrompt` 已是此模式，需核对
   清洁模式 `CleaningModeViewModel` 入口是否也遵守）。

4. **设置页分组体现边界**。在 `SettingsView` 中把功能分为「监控（核心）」与
   「附加工具（默认关闭）」两组，让用户一眼看出哪些是可选的越界能力。

### 产出

- 代码改动：`AppDelegate.swift`、`SettingsManager.swift`、`SettingsView.swift`，
  四份 `Localizable.strings` 新增开关文案。
- 文档：本节的"冷启动检查单"沉淀到 `CLAUDE.md` 的"What this app is not / 默认形态"段。

---

## P2 · 文档同步 ✅ 已完成（2026-06-26）

**目标**：让 `CLAUDE.md` / `AGENTS.md`（互为镜像，必须同步改）重新成为可信的事实来源。

> **完成记录**：`CLAUDE.md` / `AGENTS.md` 文件树补齐全部缺失文件并修正 `UpdateProgressView`→
> `UpdateWindowView`，两份镜像保持逐字节一致；Lint 阈值表改为 `.swiftlint.yml` 真实
> warning/error 数字（方案 A，并标注当前刻意宽松）；`.swiftlint.yml` 无效规则 `unowned_guard`
> 改名为 `unowned_variable_capture`（代码无 `unowned` 用法，改后 `--strict` 0 违规）；Services
> 层新增 Shape C（带 `CGEventTap` 的 `@MainActor` 生命周期服务）说明；`PRODUCT.md` 改为
> "监控核心 + 默认关闭附加工具" 定位并补 Gemini；四份 README 同步新定位、窗口管理单一开关、
> 设置分组，并把 `xcodebuild test` 说明诚实标注为"测试 target 尚未接入，P3 完成后恢复"。
> `DESIGN.md` 经核查为纯视觉规范、不含与新定位冲突的叙事，无需改动。

### 任务

1. **修正 Layout 文件树**。补齐缺失文件，至少包括：
   `Services/`：`WindowSnappingService`、`WindowSnapPreviewService`、`MagnetHotKeyService`、
   `TitlebarGestureService`、`ScrollDirectionService`、`LaunchAtLoginService`、
   `AccessibilityPermission`；`Models/`：`MetricTrends`；`Utilities/`：`MetricHistory`、
   `WindowSnapIconProvider`；`Views/`：`QuickStatCard`、`Sparkline`、`SpinningFanIcon`、
   `ToastCenter`、`UpdateWindowView`。

2. **修正 Lint 阈值表（采方案 A）**。`CLAUDE.md` 现写的阈值（file ≤500 / func ≤80 /
   复杂度 ≤12 / type ≤400 / 参数 ≤5 / tuple ≤2 / 嵌套 ≤2）与 `.swiftlint.yml` 实际
   warning 阈值（800 / 90 / 16 / 500 / 10 / 4 / 3）不符。**采方案 A**：把文档改成真实数字、
   承认当前宽松度（当前有 13 个文件 >400 行，方案 B 收紧需先拆分超限文件，成本高、不在此次范围）。

3. **清理无效 lint 规则**。`.swiftlint.yml:24` 的 `unowned_guard` 不是 SwiftLint 规则
   （0.63.3 实际规则名为 `unowned_variable_capture`），属死配置——删除或改名为正确规则。
   顺手核对 `opt_in_rules` 其余项是否都有效，避免文档继续承诺一套并不被执行的标准。

4. **更新功能架构段**。为窗口管理、滚动反转新增"Layer Contract / 服务形态"说明（它们是
   带 `CGEventTap` 的有状态服务，归类应明确）。

5. **重写 `PRODUCT.md` 定位**。从"纯监控仪表"更新为"以监控为核心、附带默认关闭的系统工具"，
   并把"克制 = 默认关闭 + 零侵入"这条新叙事写清楚，化解"监控可信度"与"event tap 侵入性"
   之间的张力。

6. **同步 README 系列**（en/zh/ja/ko）与 `DESIGN.md` 落地页叙事，使其与新定位一致。
   其中 README 关于 `xcodebuild test` 的说明需在 P3 接入测试 target 后才恢复为真。

### 产出

- 纯文档 PR。注意 `CLAUDE.md` 与 `AGENTS.md` 任一改动必须同步另一份。

---

## P3 · 测试地基 ✅ 已完成（2026-06-26）

**目标**：在重构 AI 服务之前先建立安全网，并保护最核心的健康分逻辑。纯新增，不动生产代码。

> **完成记录**：用 `ruby script/add_test_target.rb`（xcodeproj gem）把 `LightStatsTests`
> 单元测试 target 接入工程，新增共享 `Light Stats` scheme（含 Test 动作），`LightStatsTests/`
> 用 synchronized folder group 自动纳入新文件/fixture。`xcodebuild test` 跑通 **46 个测试全绿**。
> 新增 `HealthScoreServiceTests`（20）、`SettingsDefaultsTests`（8）、`AIUsageParsingTests`（11，
> 配 `Fixtures/*.json`），并把过期的 `LightStatsSmokeTests` 重写为与真实模型一致（7）。
> 为可测性加了最小生产 seam（非行为变更）：`SettingsManager` 改 `init(defaults:)` 依赖注入；
> Claude/Codex 抽出 `parseUsageJSON(Data)`、Gemini 把 `parseQuotaResponse` 提为 internal，
> 三者均被 fixture 覆盖，作为 P4 回归基线。CI（`build.yml`）在 build 前新增 Test step。
> 两处踩坑已沉淀进 CLAUDE/AGENTS 的 Tests 段：① 测试宿主在 app target 内，需重写过期 smoke
> test 才能编译；② 新建 `@MainActor` `SettingsManager` 实例析构会触发 macOS 14.x 上
> Swift Concurrency back-deploy 的 double-free（生产单例从不析构，仅测试可见），故测试里
> 持有实例不释放规避。`swiftlint --strict` 0 违规、本地化校验通过。

### 任务

0. **【step 0，阻塞其余全部】把测试 target 接入 Xcode 工程并跑通空测试**。当前
   `project.pbxproj` 只有 app target，没有 unit-test-bundle target，也没有带 Test 动作的
   shared scheme——现有 `LightStatsSmokeTests.swift` 根本进不了 CI。先：
   - 新增 `com.apple.product-type.unit-test-bundle` target（`TEST_HOST` 指向 app）。
   - 创建 shared `.xcscheme` 并启用 Test 动作，纳入 `LightStatsTests`。
   - 确认 `xcodebuild test -project "Light Stats.xcodeproj" -scheme "Light Stats" -destination 'platform=macOS'`
     能跑通现有 smoke test（绿）。**这一步绿之前，下面所有测试都是空中楼阁。**

1. **`HealthScoreService` 单元测试**（最高优先，纯静态函数，零外部依赖）：
   - 每个维度分段插值的拐点（如 CPU 50/85、memory swap 2%/10%/25%、load 0.7/1.0/2.0、
     temp 60/85、gpu 70/90）。
   - 维度缺失 / 关闭时的权重重分配（renormalize）。
   - 全维度关闭 → `HealthScore.perfect`(100)。
   - bottleneck cap：单一性能维度饱和时 `total = min(raw, worst+25)`。
   - EMA 平滑（α=0.35）的收敛方向。
   - 参考：`script/` 下已有压测脚本（CHANGELOG v1.3.0 提到的评分压测），可复用为断言基线。

2. **默认值回归测试**：断言全新 `SettingsManager`（干净 UserDefaults）下所有"附加功能"
   开关为 `false`、`exitNodeDetectionEnabled == false`、三个 AI 开关为 `false`。这条测试
   把 P1 的"默认关闭"原则钉死，防止未来误改默认值。

3. **AI 用量解析 fixture 测试**：为 Claude / Codex / Gemini 各准备真实响应样本
   （脱敏后放入 `LightStatsTests/Fixtures/`），测试纯解析函数对正常 / 缺字段 / 限流 /
   过期 token 等响应的处理。**这是 P4 重构的回归基线**——必须在重构前覆盖现有行为。
   - 前置：可能需要把现有服务里"解析"与"取数（PTY/curl/网络）"两段先做最小拆分，
     使解析函数可在无副作用下被测试调用。

4. **CI 接入**：当前 `build.yml` 跑 lint + build，但因 step 0 缺失并未真正跑测试。在 step 0
   完成后，把 `xcodebuild test` 加入 CI（或新增 test job），保证 PR 红绿可见。

### 产出

- `LightStatsTests/HealthScoreServiceTests.swift`
- `LightStatsTests/SettingsDefaultsTests.swift`
- `LightStatsTests/AIUsageParsingTests.swift` + `LightStatsTests/Fixtures/*.json`

---

## P4 · AI 用量服务抽象 ✅ 已完成（2026-06-26）

**目标**：消除 `ClaudeUsageService`(796) / `CodexUsageService`(494) / `GeminiUsageService`(512)
三者约 1800 行的重复（凭证读取、PTY/curl/API 三级兜底、重试、stale 处理），各 provider
只保留"端点 + 解析"差异。**前置条件：P3 的 AI 解析 fixture 测试已就位。**

> **完成记录**：核对后发现真正的重复集中在 **PTY 取数引擎**（Claude `/usage` 与 Codex
> `/status` 的 `capturePTYOutput`/`capturePTYSync`/`stripANSICodes`/写-全 几乎逐字相同，各
> ~120-150 行），Gemini 走纯网络（URLSession + 独有 curl-config 兜底 + OAuth refresh），不参与。
> 因此**有意偏离草案的文件名**（`AIUsageFetcher`/`CredentialSource`）：抽真正消重的两个具体机制——
> `Services/AIUsage/PTYProbe.swift`（参数化 PTY 捕获引擎：winsize/args/initDelay/command/完成谓词/
> 轮询间隔 + 一个 `onOutput` 决策闭包，Codex 的「关掉更新横幅」交互即由闭包内 write+sleep 实现）
> 与 `KeychainCredentialReader.swift`（`security` CLI 读 Keychain，零授权弹窗，原 Claude 私有逻辑提为共享）。
> Claude/Codex 各自只留 `cliProbeConfig()` 配置 + 解析；行为逐字保留，常量不变。**不强抽**统一
> `AIUsageProvider` 协议/协调器（三家返回类型不一、无共享管线，按草案指引推迟）。逐家迁移、逐家
> 验证：Codex 502→388 行、Claude 799→652 行。PTY 引擎新增 `PTYProbeTests`（合成 shell 脚本驱动，
> 覆盖完成谓词/超时/缓冲重置/ANSI 剥离）作为回归网——真实 CLI 的 TUI 路径在测试宿主里跑不通
> （与重构前同因，非回归），故以引擎单测 + 逐字转写 + JSON fixture 兜底。共 51 测试全绿、
> `swiftlint --strict` 0 违规。剩余 backlog：合并 Claude/Codex 的 reset-date 解析（差异大、CLI
> 解析路径无 fixture，本轮不动）。

> 重要约束（来自第二方评审）：**不要用单个 `AIUsageFetcher` 一次性吞掉三家的状态机**。
> 三家取数语义差异很大——Claude/Codex 走 PTY/curl fallback，Gemini 走 OAuth refresh +
> token persistence（见 CLAUDE.md 对 `GeminiUsageService` 的 "OAuth refresh flow" 标注）。
> 因此先抽**两个正交的薄层**（凭证读取、HTTP/响应解析外壳），把取数策略留在各 provider 内，
> 再逐家迁移。先求"消重 + 可测"，不强求三家共用一个取数管线。

### 设计草案（分两层，故意不统一取数管线）

```swift
// Models 层：统一用量快照（已有 AIUsageInfo，按需扩展）
struct AIUsageInfo: Sendable { /* provider, used, limit, resetAt, ... */ }

// 层一：凭证读取（三家共用——文件优先 + security CLI 读 Keychain，零授权弹窗）
enum AICredentialSource { case file(URL), keychain(service: String) }
protocol AICredentialReading {
    func read(_ sources: [AICredentialSource]) async -> Credential?
}

// 层二：HTTP/响应解析外壳（纯函数 parse 可被 P3 fixture 直接覆盖）
protocol AIUsageProvider: Sendable {
    var id: AIProvider { get }
    func parse(_ raw: Data) throws -> AIUsageInfo        // ← P3 已覆盖此函数
}

// 取数策略保留在各 provider 内部，不抽公共 fetcher：
// - Claude/Codex：file → PTY → curl 兜底
// - Gemini：OAuth refresh → 持久化新 token → 请求
```

### 任务

1. 抽出层一：共享凭证读取（`security` CLI 读 Keychain，CHANGELOG v1.5.2 的零授权弹窗实现）
   + `CLIBinaryResolver` 协作，三家复用。
2. 抽出层二：把每家的"响应 → `AIUsageInfo`"解析提成独立纯函数（P3 已覆盖），与取数副作用解耦。
3. **逐家迁移**（Claude → Codex → Gemini，各自独立提交），每迁一家就跑该家的 fixture 测试；
   取数策略差异保留在 provider 内，不强行塞进公共管线。
4. 仅在三家迁移完、确认无共性损失后，再评估是否值得抽更高层的协调器；否则 `AIUsageMonitor`
   保持面向 `[any AIUsageProvider]` 迭代即可。
5. 全程以 P3 的 fixture 测试为绿灯标准；重构后对相同响应的输出应逐字节一致。

### 风险与缓解

- 三家兜底细节差异大（PTY 需求、OAuth refresh、超时、限流码）——**逐家迁移、逐家跑测试**，
  绝不一次性替换三家。
- Gemini 的 token 持久化是有状态副作用，迁移时务必保留写回逻辑，否则会反复触发 refresh。
- 重构后单文件应显著低于现状，顺带缓解文件超限问题。

### 产出

- 新增 `Services/AIUsage/AIUsageProvider.swift`、`AIUsageFetcher.swift`、
  `CredentialSource.swift`；瘦身后的三个 provider 文件。

---

## P5 · 模块化收尾与轻量回归

**目标**：把"默认关闭 + 轻量"从原则变成持续可验证的约束。

> 验收口径必须可复跑、可观测，不能是"~50MB"这种主观描述。下列命令即验收脚本，
> 结果连同机器型号 / macOS 版本一并记入基线文档。

### 任务

1. **冷启动轻量基准（给出可复跑命令）**。在干净 UserDefaults + 默认配置下测量并记录：
   - 常驻内存（RSS）：`ps -o rss= -p "$(pgrep -x 'Light Stats')"`（KB；目标 ≲ 51200，即 ~50MB）。
   - 线程数：`ps -M -p "$(pgrep -x 'Light Stats')" | wc -l`。
   - 有无 event tap：默认形态下断言为 0 个由本 app 创建的 `CGEventTap`
     （可用 `log stream` 或代码内计数器导出；至少人工核对 scroll/keyboard/titlebar 全关）。
   - 出站请求：默认（关闭 `autoCheckUpdates`）下用 `nettop -p "$(pgrep -x 'Light Stats')" -l 1`
     或 Console 网络日志确认无连接。
   - 把以上数值 + 机型 + macOS 版本写入 `docs/lightweight-baseline.md` 作为回归基线。
2. **功能开关一致性**：核对每个附加功能"关闭后完全静默"——无定时器、无 tap、无观察者
   残留。重点确认**运行期关闭路径**（用户在设置里关掉时）与 `applicationWillTerminate` 同样
   彻底地 `stop()`，而不只是停在退出时。
3. **可选：能力分组打包**。若未来想进一步降负，可评估把窗口管理 / 滚动反转做成编译期
   或运行期可裁剪的模块（非必须，记录为 backlog）。

### 产出

- `docs/lightweight-baseline.md`（含上述可复跑命令、实测数值、机型/系统版本）。
- backlog 记录。

---

## 验收总览（Definition of Done）

- [ ] 全新安装、零配置：菜单栏仅监控项，无窗口控制图标，无权限弹窗，无出站请求
      （更新检查除外），常驻内存 ~50MB。
- [ ] `CLAUDE.md` / `AGENTS.md` 文件树与 lint 阈值与代码/配置一致，两份镜像同步；
      `.swiftlint.yml` 无效规则（`unowned_guard`）已清理。
- [ ] `PRODUCT.md` 与 README 系列反映"监控核心 + 默认关闭附加工具"的新定位。
- [ ] 测试 target 已接入 Xcode 工程，`xcodebuild test` 真正运行；`HealthScoreService`、
      默认值、AI 解析均有测试，CI 中可见红绿。
- [ ] 三个 AI service 收敛到统一 `AIUsageProvider` 抽象，行为由 fixture 测试保证不回归。

## 不在本计划范围

- 不新增监控指标或新功能（先收敛，再扩张）。
- 不引入第三方运行时依赖（维持零依赖）。
- 不改变健康分算法本身（仅补测试；调权重是独立决策）。
</content>
</invoke>

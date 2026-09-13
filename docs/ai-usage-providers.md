# AI 用量监控 · Provider 路线图与实现规格

> 状态：已落地（选型原则、A/B 档研究与排除名单仍有效；实现状态见本节末尾的「落地记录」）。
> 已实现 15 个 provider（Claude Code / Codex / Gemini / Grok / Warp / Trae / OpenCode Go / Cursor / Kimi / Qoder / DeepSeek / Z.ai / MiniMax / OpenRouter / MiMo），详见 `Light Stats/Services/AIUsage/UsageProviderRegistry.swift`。
> 取代已删除的 `docs/ai-usage-plan.md`（Phase 1 计划）与 `docs/ai-usage-providers-research.md`（2026-06-17 对标调研）。
> 对应代码：`Light Stats/Services/{Claude,Codex,Gemini}UsageService.swift`、`Light Stats/Services/AIUsage/`、
> `Light Stats/ViewModels/AIUsageMonitor.swift`、`Light Stats/Views/Popover/Components/AIUsageCard.swift`。

## 目标与硬约束

**只做一件事：告诉用户「我还剩多少」和「什么时候重置」。** 不做成本统计、不做 token 明细、不做历史图表、不做本地 JSONL 解析。

约束（沿用产品既有红线）：

- 每个 provider 独立开关，默认关闭；关掉 = 不轮询、不读凭证、零请求
- 不请求辅助功能权限；不请求 Full Disk Access
- 不读浏览器 cookie / localStorage
- 凭证读取不得弹系统授权框（`Security.framework` 的 `SecItemCopyMatching` 会弹；`/usr/bin/security` 子进程不会）

## 选型原则

### 按「订阅套餐」选，不按 IDE / harness 品牌选

品牌追不住，套餐追得住。**Windsurf 三年换了两次名字**：Codeium → Windsurf → **Devin Desktop**（Cognition 于 2026-06-02 改名，`windsurf.com` 现在 308 跳 `devin.ai/desktop`，本机实测）。按品牌维护的 provider 会在某天突然全是死代码。而「GLM Coding Plan 还剩多少」「Kimi Code 周额度还剩多少」这种订阅配额，厂商不会随便改语义。

### 覆盖度目标

不追 69 家长尾（CodexBar 的规模）。目标是**用最低成本覆盖绝大多数人真正在用的订阅**。候选人的实量排序与两个必须避开的坑见下一节。

### 认证方式决定难度，且只有三档

| 认证方式 | 难度 | 工作量（以现有实现校准） | 代价 |
|---|---|---|---|
| **本地凭证文件 / API token** | 低 | ~150–250 行 | 零弹窗 |
| **OAuth device flow** | 中 | ~250–400 行 + 一次性浏览器授权 UI | 用户要走一次授权 |
| **浏览器 cookie / localStorage** | 高 | 600–1300 行/家 | 要 Full Disk Access，cookie 名随版本变 |

现有实测行数：`ClaudeUsageService` 660 行、`GeminiUsageService` 515 行、`CodexUsageService` 404 行（都含完整降级链）。**一个纯 API token 型 provider 应该能压到 200 行以内。**

---

## 度量：厂商调研和讨论声量都不可信

选 provider 时唯一可靠的依据是**可量化的第三方口径**。厂商自述有利益相关；社区热度会往反方向骗人。

### 三个客观口径（2026-09-11 本机实测）

**npm 周下载量** —— 最能反映 CLI 的真实装机：

| 包 | 周下载 |
|---|---:|
| `@openai/codex` | 13,156,260 |
| `@anthropic-ai/claude-code` | 8,554,147 |
| `@github/copilot` | 1,929,664 |
| `opencode-ai` | 1,310,980 |
| `@google/gemini-cli` | 237,533 |
| `@qwen-code/qwen-code` | 36,604 |
| `cline` | 29,643 |

**VS Code 扩展累计安装量** —— 插件形态的工具（官方市场 `extensionquery` API）：

| 扩展 | 安装量 |
|---|---:|
| `GitHub.copilot-chat` | 78,165,145 |
| `anthropic.claude-code` | 25,269,060 |
| `saoudrizwan.claude-dev`（Cline） | 5,278,770 |
| `Google.geminicodeassist` | 5,237,823 |
| `Continue.continue` | 4,113,970 |
| `Codeium.codeium`（Windsurf 插件） | 3,977,309 |
| `Alibaba-Cloud.tongyi-lingma`（**Qoder CN**） | 2,695,015 |
| `RooVeterinaryInc.roo-cline` | 1,997,604 |
| `aminer.codegeex` | 1,353,584 |
| `Tencent-Cloud.coding-copilot`（CodeBuddy） | 621,568 |
| `BaiduComate.comate`（文心快码） | 396,078 |

**GitHub star**：`sst/opencode` 206,540 / `anthropics/claude-code` 144,696 / `openai/codex` 123,167 / `google-gemini/gemini-cli` 106,910 / `QwenLM/qwen-code` 27,762 / `zai-org/CodeGeeX` 8,804

### 三条必须记住的结论

**1. 声量和实量会背离，而且是往反方向。**

| | star 排名 | 实量排名 |
|---|---|---|
| opencode | **第 1**（206k） | 第 4（npm 131 万） |
| codex | 第 3 | **第 1**（npm 1,316 万） |

OpenCode 是全仓库 star 第一，实际下载量比 Codex **低一个数量级**。讨论热度远高于装机量。「看讨论声量」听起来比「看厂商调研」客观，但它同样会骗人，只是骗的方向不同。

**2. 单一口径会误判。** Gemini 的 npm 只有 23 万（看着像小角色），但扩展 524 万 —— 它主要走 IDE 扩展和 gcloud 分发，不走 npm。只看一个口径会把它排到最后。**至少两个口径交叉看。**

**3. 装机量 ≠ 该不该支持。** 判断标准不是「谁火」，而是「**谁的订阅有配额窗口、且能被程序读到**」。Copilot 装机体量最大，但它个人版本来就不展示用量窗口；反过来一个装机量小、但明确有 5h/周额度的 provider 更值得做。

### 国内候选人的实量排序（含两个修正）

按扩展安装量：**Qoder CN** 2,695,015 > **CodeGeeX** 1,353,584 > **CodeBuddy** 621,568 > **Comate** 396,078。

但直接拿这个排序去选人会错两次：

- **Qoder CN 就是通义灵码**，不是两个产品。阿里云 2026-05-20 官方公告把中文名「智能编码助手通义灵码」改为「Qoder CN」，英文名由 AI Coding Assistant Lingma 改为 Qoder CN。
- **CodeGeeX 的 135 万是存量，不是活跃。** `zai-org/CodeGeeX` 仓库最后 push 是 **2024-08-13**，近两年无提交；智谱的编程重心已转到 GLM Coding Plan。属于「有存量、没未来」。
- **Trae 在这里测不到** —— 它是独立 IDE，没有 VS Code 扩展，市场口径覆盖不到，只能靠它自己的接口能力判断（见 A 档）。

### 一个反例：早前那轮「调研数据」

上一版文档里引用的份额数字（JetBrains 2026-04 调查经 IdeaPlan 汇总：Copilot 4.7M 付费 / Cursor $2B ARR / Claude Code 46% most-loved、长尾 15–20%）是**二手转引**，样本偏差与赞助关系都不透明，**已被本节的一手数据取代**。以后引用市场份额必须标注来源性质。

---

# 现状（2026-09-14：15 家已实现）

最初实现 3 家，全部走「自动读本地凭证」，无需用户输入任何东西：

| Provider | 认证来源 | 端点 |
|---|---|---|
| Claude Code | Keychain `Claude Code-credentials`，经 `/usr/bin/security` 读 | `api.anthropic.com/api/oauth/usage` |
| Codex | `~/.codex/auth.json` | `chatgpt.com/backend-api/wham/usage` |
| Gemini | `~/.gemini/oauth_creds.json` | `cloudcode-pa.googleapis.com` |

外加 `UsageWarmupService`（自动续期窗口，opt-in）。

后续扩到 15 家：Grok（`~/.grok/auth.json` + CLI billing）、Warp（GraphQL）、Trae CN（credit pool，session cookie）、OpenCode Go（usage API）、Cursor（`state.vscdb`，`ideDatabase`）、Kimi（`/coding/v1/usages`，周 + 5h）、Qoder（big-model credits，session cookie）、DeepSeek / Z.ai / MiniMax / OpenRouter（API token，余额型）、MiMo（console balance + Token Plan）。凭证分三类（`CredentialSource`）：`localDiscovered`、`apiToken`（设置页粘贴，经 `KeychainCredentialWriter` 走 `security -i` 存 Keychain）、`ideDatabase`。

Overview 展示规则：多窗口 provider 折叠为一行，只显示最紧的窗口（`AIUsageWindowPicker.mostStrained`），点击展开全部；余额型 provider 沉底、无进度条（`BalanceRow` 只渲染金额）。

## ⚠️ 一个必须先补的架构缺口（已补：随 DeepSeek 落地）

**项目现在没有「用户粘贴 API key」的能力。** 三家都是自动读本地凭证，所以从来没做过输入与安全存储。

而下面 A 档里的 z.ai / MiniMax / DeepSeek / OpenRouter / Warp **全都是 API token 型** —— 用户不在本地装 CLI，我们就没有凭证可读。

所以 **A 档的第一个前置任务是**：

1. 设置页加一个「API token」输入行（`SecureField`，可清除）
2. 存 **Keychain**（不是 UserDefaults —— `SettingsManager` 现有的 `activationCode` 落 UserDefaults 是因为那是签名载荷、非机密；**usage token 是机密**）
3. 需要一个 `KeychainCredentialWriter`（现只有 Reader），写 `security add-generic-password -U`
4. 四语言文案，并说明这个 token 只用于读用量、不会被上传

**这个前置不做，A 档一家都开不了工。**

---

# A 档 —— 建议做（除 Copilot 外均已实现）

> 落地记录（2026-09-14）：z.ai / Trae（CN credit pool，session cookie 落地）/ Kimi（`/coding/v1/usages`）/ Grok（本地 CLI billing）/ MiniMax / DeepSeek / OpenRouter / Warp 均已实现。Trae 的 macOS token 落地走 session-cookie 方案。仅 Copilot（OAuth device flow）未做。

都按「贴一个 token」或「读一个本地文件」即可拿到用量，预计单家 150–250 行。

| Provider | 认证 | 窗口 | 备注 |
|---|---|---|---|
| **z.ai / GLM Coding Plan** | API token | 5h + 每小时 + 团队配额 | 你点名要。国产订阅量最大 |
| **Trae** | 本地 token（详见下节） | 积分制，非窗口 | 你点名要。**接口全文已知，见下节** |
| **Kimi / Moonshot** | JWT（`kimi-auth` cookie 里的） | 周 + 5h 限流 | API key 那个是余额，不是 coding plan 额度，别混 |
| **Grok / xAI** | Grok CLI billing RPC（本地） | 有 | 你点名要。**优先走本地 CLI，不要走 grok.com 会话** |
| **MiniMax** | API token | coding plan 窗口 | 也有 cookie 路径，别用 |
| **DeepSeek** | API key | 余额（付费/赠送分列） | 最简单的一家，适合当前置任务的验证靶子 |
| **OpenRouter** | API token | 余额 | 中转用户的实际入口 |
| **Warp** | API token（GraphQL） | 月额度 + 请求限制 | |
| **Copilot** | GitHub device flow | 月/周 | 覆盖面大，但要走 OAuth（中档） |

## Trae 实现规格（可直接开发）

**这是全文最完整的一节。** 数据来自开源项目 `star620/TRAE-Checkin` 的 `Api/TraeApiClient.cs`（GPL-3.0）—— 属**第三方逆向报告，未在本机复测**，实现时先用真 token 打一遍验证。

### CN 版与国际版是两个 provider

`trae.cn`（CN）与 `trae.ai`（国际）账户和积分体系完全独立。本节的 `api.trae.cn` 只对 CN 有效；国际版推测同构（`api.trae.ai`），**需实测确认**。建议先只做 CN。

### 请求

```
BaseUrl: https://api.trae.cn

Headers:
  Authorization: Cloud-IDE-JWT <token>
  X-User-Region: cn
  x-device-id: <16 位数字 Aha 设备号>
  Content-Type: application/json
```

**⚠️ 风控硬坑**：`x-device-id` 必须是 **16 位数字**的 Aha 设备号。用 GUID/UUID 会触发风控，返回 `9074`「参与用户太多」。这不是重试能解决的 —— 必须先把设备号拿到并存下来。

### 读剩余积分

```
POST /trae/api/v2/pay/user_current_entitlement_list   body: {}
```

```jsonc
{
  "user_entitlement_pack_list": [
    {
      "entitlement_base_info": { "quota": { "credits_limit": 4000 } },   // 总额度
      "usage":                  { "credits_amount": 512 }                // 已用
    }
  ]
}
```

`剩余 = Σ(credits_limit − usage.credits_amount)`，逐包累加，单包出现负值按 0 计。

对 Light Stats 的映射：这是一个**积分池**，不是「5h/7d 窗口」。`UsageWindow` 现有模型（label / usedPercent / resetsAt）能塞下 —— 用一条 `label = "credits"`、`usedPercent = used/limit` 的窗口即可，`resetsAt` 为 nil（积分按月刷新，接口本身不返回重置时间）。

### Token 获取与续期

- **来源**：登录后浏览器 `localStorage` 里的 `Cloud-IDE-Token`（JWT）
- **续期**（8 小时有效期）：

```
POST /cloudide/api/v3/common/GetUserToken
Cookie: X-Cloudide-Session=<session>
Referer: https://www.trae.cn/
Origin: https://www.trae.cn
→ Result.Token
```

### macOS 落地位置 —— 待实测

这是本 provider 唯一的未决项，必须在动手前解决。Trae IDE 是 VS Code fork（Electron），候选位置：

1. `~/Library/Application Support/Trae/User/globalStorage/state.vscdb`（SQLite，Cursor 就存这儿）
2. 系统 Keychain（VS Code 系用 `safeStorage` 加密后存 Keychain）
3. `~/Library/Application Support/Trae/` 下的某个 JSON

**如果三处都没有直接可用的明文 token**，退路是让用户手动粘贴 `Cloud-IDE-Token` —— 那就更依赖上面那个前置的「用户输入 token」能力，反而更简单。`x-device-id` 同理，优先从本地读，读不到就让用户粘贴或在本地持久化一次。

### 不做的事

`checkin_credits/status` 和 `checkin_credits/claim`（每日签到）**不做**。那是刷积分的自动化，不属于「读用量」，而且会带来 ToS 风险。

---

# B 档 —— 值得做，但必须吃 cookie

| Provider | 认证 | 说明 |
|---|---|---|
| **Cursor** | IDE 本地数据库（`state.vscdb`，`ideDatabase`） | 用户量极大；cookie 路径被否决，未采用 |
| **OpenCode Go** | usage API + 本地 SQLite | **Go 版有 API 路径**，比 cookie 版好做；普通 OpenCode 是 cookie |
| **Qwen Cloud / 阿里 Coding Plan** | web cookie 或 API key | 国产里量最大的之一，**先确认有没有 API key 路径** |
| **Qoder CN** | cookie | 原「智能编码助手通义灵码」，2026-05-20 官方改名，是同一个产品。扩展装机 270 万，国内最大 |
| **Kiro** | CLI-based（本地） | 月额度，可能实际属于 A 档，值得先探 |

---

# 明确排除

**维持项目原有立场，不因为「别人做了」而改。**

| 类别 | 例子 | 理由 |
|---|---|---|
| 纯 cookie 长尾 | Venice / Chutes / ZenMux / Neuralwatt / Abacus / T3 Chat / ZoomMate / Manus | 单家 600–1300 行，cookie 名随版本变，收益极小 |
| 需 Safari cookie + Full Disk Access | — | 直接违反项目的权限红线 |
| **CodeBuddy / WorkBuddy** | 腾讯 | **无可用的积分接口**，见下 |
| **CodeGeeX** | 智谱 | **存量死产品**：`zai-org/CodeGeeX` 仓库最后 push 2024-08-13，智谱重心已转 GLM Coding Plan |
| **Comate（文心快码）** | 百度 | 无可用的额度接口，只有 web 个人中心 |
| **Windsurf** | — | **品牌已不存在**（2026-06-02 改名 Devin Desktop） |
| Devin | Chrome localStorage | 品牌在，但认证走 cookie/localStorage，且定位是企业 agent 平台 |
| Cursor/Windsurf 式 IDE 品牌 | — | 品牌三年两改名，按品牌维护是负资产 |

## CodeBuddy / WorkBuddy 为什么不做的依据

查过一手官方文档：

- `codebuddy --serve` 的 HTTP API（`codebuddy.ai/docs/cli/http-api`）**有** `/api/v1/stats` 和 `/api/v1/stats/session`，但那是**本机 token / 会话统计**，不是账户积分余额
- CLI 参考（`codebuddy.ai/docs/zh/cli/cli-reference`）里**没有任何积分相关命令**
- 积分余额只在**官网个人主页 → 用量**可见（`codebuddy.ai/docs/zh/ide/Account/usage`）
- WorkBuddy 的积分同样「通过 CodeBuddy 官网个人主页查看」

结论：要做得吃 web session cookie → 落在排除档。**如果将来 CodeBuddy 开放积分 API，再重新评估。**

---

# 实施顺序（已执行完毕，保留作记录）

```
P0  前置：用户 API token 输入 + Keychain 写入（A 档全部依赖它）
      └─ 用 DeepSeek（最简单的一家）做验证靶子
P1  Trae：先解决 macOS token 落地位置；接口字段已全部已知
P2  z.ai / GLM Coding Plan、Kimi、Grok、MiniMax、OpenRouter、Warp
P3  Copilot（OAuth device flow，中等工作量）
P4  B 档按用户呼声挑，Cursor 优先
```

---

# 证据与来源

标注每条结论的可信度，避免以后把二手当一手复述。

## 一手（本机实测 / 官方文档 / 官方公告）

| 结论 | 来源 |
|---|---|
| npm 周下载量、VS Code 扩展安装量、GitHub star 三组数字 | 本机调用 npm registry API、市场 `extensionquery` API、`gh api`（2026-09-11） |
| `windsurf.com` 308 → `devin.ai/desktop` | 本机 `webfetch` 实测 |
| Windsurf 于 2026-06-02 改名 Devin Desktop | `devin.ai/blog/windsurf-is-now-devin-desktop` |
| 「智能编码助手通义灵码」于 2026-05-20 改名 **Qoder CN** | `aliyun.com/product/news/28971`、`help.aliyun.com/zh/lingma/...` |
| CodeGeeX 已无活跃开发 | `gh api repos/zai-org/CodeGeeX` → `pushed_at = 2024-08-13` |
| CodeBuddy 无积分 API，余额仅在个人主页 | 官方 docs：`cli/http-api`、`cli/cli-reference`、`ide/Account/usage` |

## 二手（引用，未复测）

| 结论 | 来源 | 风险 |
|---|---|---|
| Trae 的三个端点、字段、`x-device-id` 风控 | `star620/TRAE-Checkin` 的 `TraeApiClient.cs`（GPL-3.0） | **第三方逆向，字段可能已变，必须先复测** |
| 各 provider 的认证方式 | CodexBar README（69 providers 列表） | 活跃项目自述，可信度较高 |
| ~~Copilot 4.7M 付费 / Cursor $2B ARR / Claude Code 46% most-loved / 长尾 15–20%~~ | JetBrains 2026-04 调查，经 IdeaPlan 汇总 | **已被上一节的一手数据取代，不要再引用** |

## 适用所有 provider 的硬规则

实现任一 provider 之前，**先用真凭证手动打一遍接口**。所有端点都是非公开接口，字段可能随时变 —— 沿用现有做法：全量 `decodeIfPresent`，解码失败降级为 `.stale` 而不是崩。

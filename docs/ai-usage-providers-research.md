# AI 用量检测机制调研

调研时间：2026-06-17

对比三个 macOS 菜单栏 AI 用量监控项目的数据获取机制：
- **Light Stats**（本项目）
- **[CodexBar](https://github.com/steipete/CodexBar)**（steipete，最全面）
- **[Claude-Usage-Tracker](https://github.com/hamed-elfayome/Claude-Usage-Tracker)**（最深入 Claude 专项）

---

## 一、现有 Provider 对比

### Claude Code

| 维度 | Light Stats | CodexBar | Claude-Usage-Tracker |
|------|-------------|----------|---------------------|
| **数据源数量** | 1（OAuth API） | 3（OAuth / CLI PTY / Web Cookie） | 2（Web Session / CLI OAuth） |
| **凭证来源** | Keychain `Claude Code-credentials` | Keychain + browser cookie | Keychain + `~/.claude/.credentials.json` |
| **API 端点** | `api.anthropic.com/api/oauth/usage` | 同左 + `claude` CLI `/usage` + claude.ai web API | `claude.ai/api/organizations/{id}/usage` |
| **Token 刷新** | ❌ 手动 `claude login` | ✅ 后台自动 delegated refresh | ❌ 手动 |
| **限流处理** | ❌ 无 | ✅ 5 分钟冷却期 + 用户操作豁免 | ❌ 无 |
| **数据维度** | 5h + 7d utilization | session/weekly/opus/sonnet/spend limit/extra windows | session/weekly/opus/sonnet + cost/overage |
| **Fallback 链** | ⚠️ 刚刚新增：文件凭证 + Messages API header 解析 | ✅ Source Planner 自动选最优源 | ✅ session key → CLI OAuth → 系统 credentials |

**关键差异：**
- CodexBar 的 Source Planner 在启动时自动探测可用数据源，按优先级 fallback
- Claude-Usage-Tracker 的 Messages API header 技巧：OAuth endpoint 不可用时发 1-token Haiku 请求读 rate-limit 响应头
- Light Stats 原来只有单一 OAuth 路径，现已补上文件凭证读取和 Messages API fallback

### Codex / OpenAI

| 维度 | Light Stats | CodexBar |
|------|-------------|----------|
| **数据源** | 1（OAuth API） | 3（OAuth / CLI PTY / Web Dashboard） |
| **凭证来源** | `~/.codex/auth.json` | 同左 + browser cookie |
| **API 端点** | `chatgpt.com/backend-api/wham/usage` | 同左 + `codex /status` PTY |
| **Token 刷新** | 401 时重读文件一次 | 完整的 token refresh 流程 + 多账户协调 |

---

## 二、CodexBar 的 Provider 架构（40+ providers）

CodexBar 通过统一的 `ProviderDescriptor` 协议支持 40+ AI 服务商。其 Provider 按认证方式分为三类：

### 1. 文件凭证型（零授权弹窗）
读取 CLI 工具存储在磁盘的凭证文件，**无需任何系统弹窗**：

| Provider | 凭证位置 | API 端点 |
|----------|---------|----------|
| Claude Code | Keychain + `~/.claude/.credentials.json` | `api.anthropic.com` |
| Codex | `~/.codex/auth.json` | `chatgpt.com` |
| Gemini | `~/.gemini/oauth_creds.json` | `cloudcode-pa.googleapis.com` |
| DeepSeek | `~/.deepseek/config.json` | API token |
| Kimi | Settings file | Cookie-based API |
| Ollama | Local server (no auth) | `localhost:11434` |

### 2. OAuth 设备流型（浏览器授权一次）
需要用户在浏览器中完成一次 OAuth 授权，之后用 token 持续访问：

| Provider | OAuth 方式 |
|----------|-----------|
| GitHub Copilot | GitHub Device Flow（`github.com/login/device`） |
| Grok | X/Twitter OAuth |
| Perplexity | Web OAuth |

### 3. 浏览器 Cookie 型（脆弱，不推荐）
读取 Chrome/Safari 的 cookie 数据库，模拟已登录的 Web 会话：

| Provider | Cookie 来源 |
|----------|------------|
| Cursor | `WorkosCursorSessionToken` 等 session cookie |
| Windsurf | Windsurf app localStorage token |
| MiniMax | Web cookie |
| Mistral | Web cookie |

**Cookie 方式的固有问题：**
- 需要访问浏览器 SQLite 数据库（macOS 权限管控越来越严）
- Cookie 名称和格式随版本变化，持续维护成本高
- Cursor cookie importer 单文件 1332 行，Windsurf 600+ 行
- CodexBar 的 Cursor 相关测试文件超过 30 个

---

## 三、Claude-Usage-Tracker 的独特设计

该项目只做 Claude，但做得很深。几个值得注意的设计：

### 凭证文件直读（解决 Keychain 截断问题）
macOS Keychain 对单个 item 有 ~2KB 的大小限制。Claude Code 的 OAuth JSON（含 access token + refresh token + scopes + expiry）可能超过此限制，导致 Keychain 返回的 JSON 被截断。

解决方案：优先读 `~/.claude/.credentials.json`，Keychain 作为备份。

**⚠️ macOS 注意：** `.credentials.json` 是 **Linux 的默认存储格式**。macOS 上 `claude login` 只写 Keychain，**不会自动生成此文件**。需在无 GUI 场景（SSH / CI）使用时，用户手动从 Keychain 导出。普通 macOS 桌面用户通常无此文件，必然 fallback 到 Keychain → 触发系统授权弹窗。

### Hashed 服务名发现
Claude Code v2.1.52+ 将 Keychain 服务名从 `Claude Code-credentials` 改为 `Claude Code-credentials-{HASH}`。该项目通过 `security dump-keychain` 自动发现（带 5 秒超时，且整个生命周期只运行一次）。

### Messages API Rate-Limit Header 解析
当 `/api/oauth/usage` 端点不可用时（历史上确实发生过），发送一个最小成本的 Messages API 调用（Haiku 1 token），从响应头提取用量：

```
anthropic-ratelimit-unified-5h-utilization: 0.42  → 42% used
anthropic-ratelimit-unified-5h-reset: 1712345678  → reset timestamp
anthropic-ratelimit-unified-7d-utilization: 0.15   → 15% used
```

成本：~10 input + 1 output token，可忽略。

### 多账户 Profile 切换
支持多个 Claude 账户 profile，切换时自动：
1. 回写 Keychain（`security add-generic-password`）
2. 更新 `~/.claude.json` 的 `oauthAccount` 字段
3. 使 `claude /status` 命令反映正确的账户

---

## 四、对 Light Stats 的建议

### 已实施（本次调研后）
- [x] Claude Code 凭证优先读文件（0 弹窗）
- [x] Messages API header fallback（OAuth endpoint 不可用时）
- [x] `endpointNotFound` 错误细化

### 短期可做（高价值、低风险）
- [ ] **Gemini**（~200 行）：读 `~/.gemini/oauth_creds.json`，0 弹窗，和 Claude Code 模式完全一致
- [ ] **Copilot**（~250 行 + Settings UI）：GitHub Device OAuth，首次浏览器授权一次，之后 0 弹窗

### 不建议做
- [ ] Cursor、Windsurf 等依赖浏览器 cookie 的 provider — 代码量大（600-1300+ 行/个）、维护成本高、权限依赖脆弱

### 长期方向
- [ ] Provider 协议抽象：当前 Claude/Codex 各写一个 Service 文件，扩展到 4 个 provider 后应该抽取 `AIUsageProvider` 协议，让 `AIUsageMonitor` 统一调度
- [ ] 数据源 fallback 规划：参考 CodexBar 的 Source Planner 理念，为每个 provider 定义主/备数据源

---

## 五、参考资料

- [CodexBar GitHub](https://github.com/steipete/CodexBar) — 40+ provider 的参考实现
- [Claude-Usage-Tracker GitHub](https://github.com/hamed-elfayome/Claude-Usage-Tracker) — Claude 专项深度实现
- CodexBar 的 `ProviderDescriptor` 协议和 `UsageFetcher` 协议设计

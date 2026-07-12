## v1.9.0-beta.8（预发布 / Prerelease）

### ✨ 新功能 / Features

- 四主题：`glass`（展示名「默认 / Default」，冷启动默认）/ `bento` / `film`（晒金）/ `noir`（墨夜）；选择器顺序 默认 → Bento → 晒金 → 墨夜；退役 `aurora`/`paper` 键映射到 film
- 晒金与墨夜外观：颗粒开关 + 光影动态五档（静止 / 舒缓 / 自然 / 流畅 / 活跃）
- Popover / About / Toast / Update / 辅助功能引导接入主题；`ThemeTokens` + mesh 背景 + 颗粒纹理
- 指标图标改用 bundle 内 Reicon Outline SVG（`SVGIcon` 模板染色，零第三方）

### 🔧 优化 / Improvements

- 设置窗固定系统白底，不跟随 `appTheme`（主题只作用产品展示面）
- Overview / Cleanup 按主题分叉布局（Bento 卡片网格 vs instrument 读数）
- 辅助功能引导由 NSAlert 改为主题化 SwiftUI 面板（`PermissionAlertCenter`，borderless 无系统叉号）

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.9.0-beta.7...v1.9.0-beta.8

---

## v1.9.0-beta.7（预发布 / Prerelease）

### ✨ 新功能 / Features

- 更新通道可选「正式版 / 尝鲜」：开启后自动与手动检查均纳入 Beta 预发布
- 应用日志支持关 / 仅错误 / 完整三级，结构化诊断日志（本地、保留 5 天）
- 设置页重组为通用 / 监控 / 更多三栏，并统一白底浅色侧栏

### 🔧 优化 / Improvements

- Finder 新建文件按类型命名（index / main / notes…），不再统一 Untitled
- Finder 扩展已启用时隐藏「在系统设置中启用」；模板列表改为扁平展开
- 常用目录 / 打开方式列表改为单行「名称 + 路径」
- 分段控件等宽、说明文案更短，减少设置页折行
- SemVer 正确比较 `-beta.N`，保证 beta 递增与转正可识别

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.9.0-beta.6...v1.9.0-beta.7

---

## v1.9.0-beta.6（预发布 / Prerelease）

### ✨ 新功能 / Features

- Finder 右键菜单支持终端选择、cmux 新窗口与新工作区操作
- 设置中显示 FinderSync 扩展的真实注册与启用状态
- 自动更新默认关闭，干净安装保持零外联

### 🔧 优化 / Improvements

- AI 用量窗口保活改为在重置窗口后触发，并增加有限重试
- 清洁模式仅在便携式 Mac 上显示
- 保持唤醒归入通用设置

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.8.0...v1.9.0-beta.6

---

## v1.8.0

### ✨ 新功能 / Features

- 新增默认关闭的屏幕保持唤醒
- 新增 Finder 右键菜单、分类文件模板和模板显示开关
- 新增 Claude Code 与 Codex 用量窗口保活
- 设置、关于和更新窗口适配 Liquid Glass 背景

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.7.0...v1.8.0

---

## v1.7.0

### ✨ 新功能 / Features

- 窗口管理整合为单一总开关
- 新增登录时启动设置
- 概览指标增加短期趋势折线

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.6.0...v1.7.0

---

## v1.6.0

### 🔧 优化 / Improvements

- 完善多语言切换与更新窗口交互
- 增加轻量 Toast，并统一工具栏操作反馈

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.5.2...v1.6.0

---

## v1.5.2

### ✨ 新功能 / Features

- 改用 security CLI 读取 Keychain，彻底消除 Claude 用量采集时的授权弹窗
- 启动时不触发 Keychain 授权弹窗，优化界面交互细节

### 🔧 优化 / Improvements

- 全局 `.focusable(false)` 消除所有 AppKit 原生控件蓝色焦点环
- 简化设置界面——移除网速单位、精简刷新间隔标签

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.5.1...v1.5.2

---

## v1.5.1

### 维护性更新 / Maintenance release

- SwiftLint 零违规修复
- App 卸载残留清理调研

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.5.0...v1.5.1

---

## v1.5.0

### ✨ 新功能 / Features

- 新增 CLI PTY 和 curl fallback，消灭间歇性用量 stale
- 新增 CLI PTY 三源兜底，消灭间歇性用量 stale
- 健康分维度改为纯文字按钮，支持颜色指示器实时演示
- 新增平缓色调模式并重构设置面板布局
- 新增 Gemini CLI 用量监控
- 凭证优先文件读取实现零授权弹窗并新增 Messages API fallback
- 重构底部操作栏并添加 AI 用量重试

### 🔧 其他 / Other

- 截图导出路径改为动态解析项目根目录
- 统一数据缺失展示为 em dash 并优化多项细节

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.4.3...v1.5.0

---

## v1.3.0

- fix(ci): 修复 Liquid Glass 在旧 SDK 编译失败并将 CI 钉到 Xcode 26
- docs(site): 重塑项目站点并启用 Pages 部署
- docs(site): 添加项目展示与隐私支持页面
- feat(HealthScore): 支持自定义评分维度与调试快照
- chore(HealthScore): 添加压测脚本验证评分响应
- docs(README): 增加界面截图提升项目展示效果
- chore(lint): 明确严格检查要求并修复现有警告
- docs: 补充 CLAUDE.md 与 AGENTS.md 同步维护说明
- feat(HealthScore): 重构健康分评分算法——按系统实时压力重新选择维度
- chore: 补全项目工程化基础设施与文档体系
- feat(UI): 适配 macOS 26 Liquid Glass 视觉风格
- fix: 自动关闭逻辑从"在 AppDelegate 挂通知观察者"改成"在 KeyablePanel 子类里重写 resignKey()"
**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.2.2...v1.3.0

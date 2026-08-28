## Unreleased

### ✨ 新功能 / Added

- 找到我的鼠标：双击左修饰键（Control / Option / Command / Shift 可选）全屏压暗并聚光指针，点击或按键淡出；listen-only 事件 tap，需辅助功能权限，默认关闭
- 离线激活码：高级功能（首个为「找到我的鼠标」）需要激活码解锁；Ed25519 签名本地校验、零网络请求；`script/license-tool` 离线发码器（生成密钥对 / 发码 / 验码）
- Pro 赠送期：正式收费前启动过 App 的用户永久获赠 Pro；收费版本发布后仅新用户需要激活码
- 自动更新源改为 Cloudflare R2 渠道标记（`latest-stable.json` / `latest-beta.json`，含发布说明与 SHA-256 校验），GitHub Releases 保留为回退；正式版上传同时刷新 Beta 标记

### 🔧 调整 / Changed

- 移除电池充电管理及其特权 helper；保留电量、循环次数、健康度、功率和温度等只读监控

### 🐛 修复 / Fixed

- 应用退出恢复为即时完成，避免应用内更新停在「正在校验并安装」

## v1.9.1-beta.3（预发布 / Prerelease）

相对 **v1.9.1-beta.2** 的补丁预发布。面向用户的完整说明见 `docs/releases/v1.9.1-beta.3.md`。

### ✨ 主题 / Themes

- 主题阵容收敛为四个：经典、黄金时刻、琥珀、墨夜（干净安装仍默认墨夜）；删除 Bento 与灰纱
- 夜色酒吧改为暖琥珀灯光 + 青蓝霓虹点缀，更名「琥珀」
- 霓虹主题改用暖金黄铜仪表墨色，更名「黄金时刻」；移除两主题的竖直光束
- 默认主题更名「经典」；所有主题统一无内容卡片的 instrument 布局
- 取消「黑白界面」开关，指标动态着色恒定

### ✨ 新功能 / Added

- 滚动控制可选纳入触控板与 Magic Mouse
- 可关闭鼠标滚轮加速度，并固定每次滚动 1 到 10 行
- 新增 `Control + Option + Return` 最大化与 `Control + Option + C` 居中快捷键
- 弹窗工具栏新增保持唤醒快捷开关

### 🔧 改进 / Changed

- 设置侧栏改为通用、监控、输入设备、窗口管理、AI 用量、右键菜单六个直达入口
- 主题预览、动态配色、趋势线与标签样式重新调整
- 右键菜单文案精简为「右键菜单」

### 🐛 修复 / Fixed

- 滚动反转同时更新 CGEvent 与底层 IOHID 值，改善自然滚动开启时不同 App 的方向一致性
- 水平滚动使用独立倍率，低倍率整数步进不会再舍入为零
- 睡眠唤醒、事件 tap 超时禁用及快速切换设置后会恢复或重建滚动 tap

---

## v1.9.1-beta.2（预发布 / Prerelease）

相对 **v1.9.0** 的补丁预发布。面向用户的完整说明见 `docs/releases/v1.9.1-beta.2.md`。

### ✨ 主题 / Themes

- 恢复晒金 / 墨夜动态 mesh 背景，并隔离面板滚轮
- 重塑墨夜月光与水墨云层；自然光影更顺滑
- 设置页主题预览放大；工具窗回归系统外观
- 冷启动默认主题改为墨夜

### 🐛 修复 / Fixes

- 修复浮层空白区域点击穿透到下方窗口
- 取消标题栏手势时不再错误提交窗口吸附

### 🔧 优化 / Improvements

- 合并主题网格背景绘制，降低渲染开销

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.9.1-beta.1...v1.9.1-beta.2

---

## v1.9.1-beta.1（预发布 / Prerelease）

相对 **v1.9.0** 的补丁预发布。

### 🐛 修复 / Fixes

- 修复晒金 / 墨夜主题下总览与清理页滚动时，滚轮穿透到面板后方窗口的问题（macOS 26 更明显）
- 修复更新窗口中较长 release notes 把安装/下载按钮顶出屏幕的问题

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.9.0...v1.9.1-beta.1

---

## v1.9.0

相对 **v1.8.0** 的正式版更新（含全部 1.9.0 beta 周期内容）。
面向用户的完整说明见 `docs/releases/v1.9.0.md`（GitHub Release 正文同源）。

### ✨ 新功能 / Features

**主题与外观**

- 四种外观主题：默认、Bento、晒金、墨夜
- 晒金与墨夜支持颗粒纹理、光影动态五档调节
- 监控面板、关于、更新与权限引导统一跟随所选主题
- 指标图标升级为更清晰的 SVG 图标

**Finder 扩展**

- 右键菜单支持选择终端、cmux 新窗口与新工作区
- 设置中可查看 Finder 扩展是否已注册并启用
- 新建文件按类型自动命名（如 index、main、notes）

**更新与诊断**

- 更新通道可选「正式版」或「尝鲜（Beta）」
- 应用日志可选：关 / 仅错误 / 完整（本地保存，约 5 天）
- 自动检查更新改为默认关闭，干净安装不会主动外联

**设置与其它**

- 设置页重组为「通用 / 监控 / 更多」三栏
- AI 用量失败时可一键重试；用量窗口保活更稳妥
- 清洁模式仅在笔记本等便携式 Mac 上显示

### 🔧 优化 / Improvements

- 设置窗口固定系统浅色底，主题只作用于产品展示界面
- 不同主题下概览与清理页布局更贴合各自风格
- 辅助功能权限引导改为应用内主题化面板
- Finder 设置列表更紧凑；已启用扩展时不再提示去系统设置开启
- 诊断日志降低冗余采样与敏感信息暴露

### 🐛 修复 / Fixes

- 修复 Finder 选文件/应用面板导致滚动与手势异常
- 清洁模式下同时封锁媒体键与功能键
- 修正笔记本识别、接电未充电状态与磁盘用量小数显示
- 兼容通过 pnpm 安装的新版 Codex 路径
- 修复部分设置面板可能卡住的问题

**Full Changelog**: https://github.com/EvilIrving/light-stats/compare/v1.8.0...v1.9.0

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

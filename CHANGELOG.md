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

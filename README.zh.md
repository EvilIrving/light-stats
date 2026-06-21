# Light Stats

Light Stats 是一款原生 macOS 菜单栏系统监控工具，关注的是「你的 Mac 此刻是否吃紧」，而不只是占用了多少。0-100 健康分和 CPU、GPU、内存压力等实时信号常驻菜单栏；点开弹窗即可看到完整画面：磁盘与磁盘 I/O、网络、代理与出口节点状态、电池、温度、风扇、占用最高的进程，以及 AI CLI 用量。

[English](README.md) · **简体中文** · [日本語](README.ja.md) · [한국어](README.ko.md)

---

## 演示

<!-- DEMO VIDEO: upload docs/light-stats-readme.mp4 to a GitHub issue/release/comment box
     to get a https://github.com/user-attachments/assets/... URL, then replace the
     placeholder line below with that bare URL (GitHub renders a bare video URL as a player). -->

> 🎥 **演示视频占位** — 视频链接稍后补上。

---

## 界面预览

| 概览 | 清理 |
|------|------|
| <img src="docs/screenshots/popover-overview.png" width="320" alt="概览面板" /> | <img src="docs/screenshots/popover-cleanup.png" width="320" alt="清理面板" /> |

---

## 概览

Light Stats 将 Mac 当前的实时压力信号固定在菜单栏中，需要更多上下文时可打开详细浮动面板。它适合希望快速查看系统状态、不想常开活动监视器的用户，也适合想参考原生 SwiftUI/AppKit 菜单栏实现的开发者。

应用使用 macOS 原生 API 做常规采样，没有第三方运行时依赖，涉及外部网络的诊断功能默认关闭。

---

## 功能

### 菜单栏

- 紧凑的双行状态项，数值固定宽度，避免布局跳动
- 可选显示 Logo、CPU、GPU、内存、磁盘、网络、风扇、电池、健康分
- 网络上传和下载速率显示
- 风扇使用旋转图标表达状态
- 可选显示 0-100 健康分

### 概览面板

- CPU、GPU、内存压力、交换活动和负载均值
- P/E 核心使用率图表和 CPU 进程排行
- 电池状态、电量、循环次数、健康度、功耗和温度，按机型能力显示
- 磁盘容量和聚合磁盘 I/O 速率
- 网络速率、本地代理状态和可选公网出口节点信息
- 温度、风扇、热状态和磁盘状态条
- 系统健康分、各维度摘要和维度开关
- 开启 AI 监控后显示 Claude Code、Codex、Gemini 订阅用量

### 内存清理

- 内存压力概览和交换空间预警
- 按内存占用排序的 App 列表
- 正常关闭和二次确认后的强制退出
- 可展开查看子进程

### 窗口控制

- 可选的菜单栏窗口控制入口，菜单动作带设计师绘制的图标
- 左半屏、右半屏、上半屏、下半屏保留快捷键，覆盖最高频窗口放置操作
- 菜单提供角落、三分之一、跨显示器移动、最大化、居中、还原、最小化等动作
- 支持标题栏触控板手势，带目标区域预览和触觉反馈
- 窗口控制、全局快捷键和标题栏手势需要辅助功能权限

### 滚动方向控制

- 可选垂直和水平滚动方向反转
- 步长倍率用于微调滚动手感
- 仅在相关功能开启时启动事件 tap

### 清洁模式

- 锁定键盘 60 秒，方便擦拭键盘
- 全屏半透明遮罩和倒计时
- 鼠标点击按钮可退出，键盘输入会被抑制
- 使用 CGEventTap，需要辅助功能权限

### 自动更新

- 从 GitHub Releases 检查新版本
- 下载 DMG 后验证 codesign 签名、公证状态和 Team ID
- 应用退出后通过独立脚本替换运行中的 app bundle
- 下载和安装期间显示轻量进度窗口

### 网络与代理

Light Stats 可从环境变量、系统代理设置和活跃隧道接口检测本地代理配置，这个过程不会发起外部请求。

公网出口节点探测是可选功能。开启后，应用可向所选 geo-IP provider 查询公网 IP、位置、ASN 和 ISP，并缓存结果以避免频繁请求。

### AI 订阅用量

开启后，Light Stats 会读取 Claude Code、Codex、Gemini CLI 在本地保存的凭据，并在概览面板中显示当前订阅利用率。AI 监控默认关闭，凭据仅用于向对应 provider 自己的用量接口发起查询，不会传输至其他服务。

### 健康分

健康分将 CPU、内存压力与交换、负载均值、温度、GPU 和电源状态汇总为 0-100 分。它关注实时响应压力，而不是磁盘容量这类变化较慢的数字。笔记本使用电池状态作为电源维度，台式机使用磁盘 I/O 压力。缺失或关闭的维度会自动重分配权重。

---

## 隐私

Light Stats 没有远程遥测。本地系统指标、本地代理检测、进程列表、滚动行为和窗口控制都留在本机。

出口节点探测默认关闭。开启后，应用会向所选 geo-IP provider 发送请求，用于识别当前公网 IP 和网络归属。结果会缓存 60 秒，请求失败时会静默降级。

AI 用量监控默认关闭。开启后，请求只会发送到对应 provider 自己的用量接口，并使用该 provider CLI 已经保存在本机的凭据。

更新检查会访问 GitHub Releases。

---

## 设置

- 菜单栏项目显示开关
- 刷新频率：低 (5s)、中 (2s)、高 (1s)
- 温度单位：摄氏度或华氏度
- 网速单位：自动、KB/s 或 MB/s
- 出口节点探测和 provider 选择
- Claude Code、Codex、Gemini AI 监控开关
- 垂直滚动反转、水平滚动反转和步长倍率
- 窗口快捷键和标题栏手势
- 健康分维度开关
- 语言：简体中文、English、日本語、한국어、跟随系统

---

## 开发

详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

### 环境要求

- macOS 14+
- 推荐 Xcode 16 或更新版本
- Swift 5.9+
- 本地 lint 需要 SwiftLint (`brew install swiftlint`)

### 构建

```bash
# 构建并启动最新 Debug app
./debug-run.sh

# 手动 Debug 构建
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -configuration Debug \
  -derivedDataPath build/DerivedData build

# Release DMG
./build.sh
```

### 质量检查

```bash
swiftlint lint --strict
./validate_localization.sh
```

GitHub Actions 会运行 SwiftLint、本地化覆盖检查、Release 构建、产物上传、tag 签名/公证和 GitHub Release 创建。

### 测试

起步 XCTest 套件位于 `LightStatsTests/LightStatsSmokeTests.swift`。

```bash
xcodebuild test \
  -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -destination 'platform=macOS'
```

### 技术栈

- SwiftUI 用于面板和设置
- AppKit 用于菜单栏集成、弹出面板、遮罩和自定义视图
- Combine 与 Swift Concurrency
- Mach API、IOKit、Accessibility、Core Graphics event tap、CFNetwork、Network、SMC、getifaddrs
- 零第三方运行时依赖

### 架构

应用按模型、服务、视图模型和视图分层。`SystemMonitor` 负责编排采样并向 UI 发布快照，各服务类型分别采集对应指标。

需要缓存或异步执行的采集器，例如出口节点查询和 AI 用量 provider，使用 actor。UI 绑定状态留在主 actor。快速 syscall helper 在合适场景下保持同步。

### 项目结构

- `Light Stats/Models/`: 指标数据结构、健康分、版本信息
- `Light Stats/Services/`: 系统采集、评分、更新、滚动、窗口控制、键盘锁、AI 用量
- `Light Stats/ViewModels/`: 应用状态、采样、设置、清洁模式、更新编排
- `Light Stats/Views/StatusBar/`: 菜单栏渲染
- `Light Stats/Views/Popover/`: 浮动面板 UI 和可复用组件
- `Light Stats/Views/Settings/`: 设置 UI
- `Light Stats/Views/About/`: 关于窗口
- `Light Stats/Views/CleaningMode/`: 清洁模式遮罩
- `Light Stats/Views/Update/`: 更新进度窗口
- `Light Stats/Resources/`: 本地化字符串和窗口控制图标
- `LightStatsTests/`: XCTest smoke tests
- `.github/workflows/`: 构建、部署和发布自动化

---

## 路线图

- 更详细的网络诊断
- 覆盖 Intel、Apple Silicon、笔记本和台式 Mac 的更多验证
- 按 App 统计网络用量
- 更细的清理建议
- 持续调优窗口手势和菜单栏密度

# Light Stats

Light Stats 是一款紧凑的 macOS 菜单栏系统监控应用，可显示 CPU、GPU、内存、磁盘、磁盘 I/O、网络、代理路径、电池、温度、风扇、进程、AI 订阅用量和整体健康分。

> 英文版 README 请查看 [README.md](README.md)

---

## 界面预览

| 概览 | 清理 |
|------|------|
| <img src="docs/screenshots/popover-overview.png" width="320" alt="概览面板" /> | <img src="docs/screenshots/popover-cleanup.png" width="320" alt="清理面板" /> |

---

## 概览

Light Stats 将核心系统指标固定在菜单栏中，需要更多上下文时可打开详细浮动面板。它适合希望快速查看系统状态的普通用户，也适合想参考原生 SwiftUI/AppKit 菜单栏监控实现的开发者。

应用使用 macOS 原生 API 做常规采样，涉及外部网络的诊断功能默认关闭。

---

## 功能

### 菜单栏

- 紧凑的双行状态项
- 固定宽度数值，避免布局跳动
- 可选显示 Logo、CPU、GPU、MEM、Disk、Net、Fan、Battery、Health
- 网络上传和下载速率显示
- 可选健康分显示

### 概览面板

- CPU、GPU、内存和负载均值
- 电池状态、电量、循环次数、健康度、功耗和温度，按机型能力显示
- 磁盘容量和聚合磁盘 I/O 速率
- 网络速率、本地代理状态和可选公网出口节点信息
- 温度、风扇和磁盘状态条
- CPU 进程排行和 P/E 核心使用率图表
- 系统健康分和各维度摘要
- 开启 AI 监控后显示 Claude Code 和 Codex 订阅用量

### 内存清理

- 内存压力概览
- 交换空间预警
- 按内存占用排序的 App 列表
- 正常关闭和二次确认后的强制退出
- 可展开查看子进程

### 网络与代理

Light Stats 可从环境变量、系统代理设置和活跃隧道接口检测本地代理配置，这个过程不会发起外部请求。

公网出口节点探测是可选功能。开启后，应用可向所选 geo-IP provider 查询公网 IP、位置、ASN 和 ISP，并缓存结果以避免频繁请求。

### AI 订阅用量

开启后，Light Stats 读取 Claude Code 和 Codex CLI 在本地保存的凭据，并在概览面板中显示当前订阅利用率（5 小时和 7 天窗口）。AI 监控默认关闭，凭据仅用于向对应 provider 的用量接口发起查询，不会传输至任何第三方。

### 健康分

健康分将 CPU、内存、负载均值、磁盘占用、温度、电池和磁盘 I/O 汇总为 0-100 分。若当前机型缺少部分传感器数据，可选维度的权重会自动重分配。

---

## 隐私

出口节点探测默认关闭。本地代理检测不会联系任何外部服务。

开启出口节点探测后，应用会向所选 geo-IP provider 发送请求，用于识别当前公网 IP 和网络归属。结果会缓存 60 秒，请求失败时会静默降级。

---

## 设置

- 菜单栏项目显示开关
- 刷新频率：低 (5s)、中 (2s)、高 (1s)
- 温度单位：摄氏度或华氏度
- 网速单位：自动、KB/s 或 MB/s
- 出口节点探测和 provider 选择
- AI 监控开关（Claude Code 和 Codex 用量）
- 语言：简体中文、English、日本語、跟随系统

---

## 开发

### 环境要求

- macOS 14+（支持 macOS 26 Liquid Glass 视觉风格）
- 推荐 Xcode 16 或更新版本
- Swift 5.9+

### 技术栈

- SwiftUI 用于面板和设置
- AppKit 用于菜单栏集成和自定义绘制
- Combine 与 Swift Concurrency
- Mach API、IOKit、CFNetwork、Network、SMC、getifaddrs

### 架构

应用按模型、服务、视图模型和视图分层。`SystemMonitor` 负责编排采样并向 UI 发布快照，各服务类型分别采集对应指标。

需要缓存或异步执行的采集器，例如出口节点和电池智能数据读取器，使用 actor。轻量本地工具在合适场景下保持同步调用。

### 项目结构

- `Light Stats/Models/`: 指标数据结构
- `Light Stats/Services/`: 系统数据采集和评分逻辑
- `Light Stats/ViewModels/`: 应用状态和采样编排
- `Light Stats/Views/StatusBar/`: 菜单栏渲染
- `Light Stats/Views/Popover/`: 浮动面板 UI
- `Light Stats/Views/Settings/`: 设置 UI
- `Light Stats/Resources/`: 本地化字符串

---

## 路线图

- 外置盘识别和系统卷过滤
- 所有可见数值完整接入单位设置
- 更详细的网络诊断
- 风扇和健康分菜单栏指示的进一步优化
- 覆盖 Intel、Apple Silicon、笔记本和台式 Mac 的更多验证

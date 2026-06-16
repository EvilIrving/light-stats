# App 卸载残留清理 — 调研报告

> 调研日期：2026-06-17
>
> 参考项目：[Vorssaint](https://github.com/vorssaint/vorssaint-utils)（理念参照）、[Mole](https://github.com/tw93/Mole)（源码级参照）

## 一、现有基础：Light Stats 中可直接复用的部分

### 1.1 数据采集层（无需改动）

| 组件 | 文件 | 可复用能力 |
|------|------|-----------|
| `ProcessBundleInfo` | `Models/AppGroup.swift:50-72` | `bundlePath`、`bundleId`、`isAppleApp`、`isSystemApp` 判断 |
| `ProcessService.getBundleInfo()` | `Services/ProcessService.swift:60-90` | 从 PID → `proc_pidpath` → `.app` bundle 路径 → `Bundle(path:)` → `bundleIdentifier` |
| `AppGroup` | `Models/AppGroup.swift:84-120` | `bundlePath`、`bundleId`、`execPath`、`isAppleApp`、`isSystemApp` |
| `AppMemoryManager.buildAppGroups()` | `ViewModels/AppMemoryManager.swift:175-280` | `NSWorkspace.runningApplications` + bundle 信息提取 + 子进程合组 |

新服务可以直接消费这些类型和逻辑，不产生修改冲突。

### 1.2 UI 层（需扩展）

`CleanupTabView.swift` 目前只有两段：
- 内存使用卡片（进度条 + swap 警告）
- 运行中 App 列表（强制退出）

需新增独立的 **Uninstall** 分段：已安装 App 列表 + 残留扫描结果 + 移入废纸篓操作。

---

## 二、Mole 的核心设计

Mole 不是简单的按 App 名 `rm -rf`，而是从 `.app/Contents/Info.plist` 提取 bundle_id、可执行名和 App 名后，用多套规则找残留。

### 2.1 扫描规则分层

Mole 把扫描分为两个函数，对应两个安全级别：

**`find_app_files()` — 用户级残留**（`~/Library/` 下，无需权限）：

| 路径模板 | 匹配方式 |
|----------|---------|
| `~/Library/Application Support/{name}` | App 名匹配 |
| `~/Library/Application Support/{bundleId}` | bundle ID 精确匹配 |
| `~/Library/Caches/{name}` | App 名匹配 |
| `~/Library/Caches/{bundleId}` | bundle ID 精确匹配 |
| `~/Library/Logs/{name}` | App 名匹配 |
| `~/Library/Logs/{bundleId}` | bundle ID 精确匹配 |
| `~/Library/Preferences/{name}.plist` | App 名匹配 |
| `~/Library/Preferences/{bundleId}.plist` | bundle ID 精确匹配 |
| `~/Library/Saved Application State/{name}.savedState` | App 名匹配 |
| `~/Library/Saved Application State/{bundleId}.savedState` | bundle ID 精确匹配 |
| `~/Library/Containers/{bundleId}` | bundle ID 精确 + 前缀匹配 |
| `~/Library/Group Containers/{bundleId}*` | bundle ID 前缀匹配 |
| `~/Library/WebKit/{bundleId}` | bundle ID 精确匹配 |
| `~/Library/HTTPStorages/{bundleId}` | bundle ID 精确匹配 |
| `~/Library/Cookies/{bundleId}.binarycookies` | bundle ID 精确匹配 |
| `~/Library/Application Scripts/{bundleId}` | bundle ID 精确 + 前缀匹配 |
| `~/Library/LaunchAgents/{bundleId}.plist` + `{bundleId}.*.plist` | bundle ID 精确 + 通配 |
| `~/Library/LaunchAgents/*{name}*.plist` | App 名匹配（≥5 字符） |
| `~/Library/CrashReporter/{name}_*.plist` | App 名匹配 |

**`find_app_system_files()` — 系统级残留**（`/Library/` 下，需 sudo，Mole CLI 中默认 review-only）：

| 路径模板 | 匹配方式 |
|----------|---------|
| `/Library/Application Support/{name}` | App 名匹配 |
| `/Library/LaunchAgents/{bundleId}.plist` + `{bundleId}.*.plist` | bundle ID 精确 + 通配 |
| `/Library/LaunchDaemons/{bundleId}.plist` | bundle ID 精确匹配 |
| `/Library/PrivilegedHelperTools/{bundleId}*` | bundle ID 前缀匹配 |
| `/Library/Preferences/{bundleId}.plist` | bundle ID 精确匹配 |
| `/private/var/db/receipts/{bundleId}*` | bundle ID 前缀匹配 |

### 2.2 匹配策略（三套规则组合）

**优先级 1 — bundle_id 精确匹配**（经过 reverse-DNS 校验后）：

```
路径模板直接替换 bundle_id 字段
衍生 bundle_id 前缀匹配（Containers/Group Containers/Application Scripts 中 com.example.app.helper 也归到 com.example.app）
ByHost Preferences 文件名匹配（*{bundleId}*.plist）
```

**优先级 2 — App 名变体匹配**（当 bundle_id 无效或作为 bundle_id 匹配的补充）：

```
原始名:     "Maestro Studio"
去空格:     "MaestroStudio"
下划线:     "Maestro_Studio"
连字符:     "Maestro-Studio"
全小写:     "maestro studio", "maestrostudio", "maestro-studio"
基础名:     "Maestro"（去掉 Nightly/Beta/Dev/Preview 等版本后缀）
```

变体匹配覆盖 `Application Support`、`Caches`、`Logs`、`Preferences`、`Saved Application State`、XDG 目录（`~/.config`、`~/.cache`、`~/.local/share`）等位置。

**优先级 3 — 专项规则（vendor-specific）**：

| App | 特殊处理 |
|-----|---------|
| Xcode | 只扫 DerivedData/DeviceSupport，保护 `~/Library/Developer`（Toolchains、Archives、provisioning profiles） |
| VS Code | 显式匹配 `"Code"` / `"Code - Insiders"` 文件夹名（与 bundle id `com.microsoft.VSCode` 命名不一致） |
| Android Studio | 只扫 `~/.android/cache` 等 regenerable 目录，保护 SDK/AVD/keystore |
| Docker | 只扫 `~/.docker/buildx` 等 cache，保护 `~/.docker/config.json`（auth tokens） |
| JetBrains IDE | 限定到具体产品名（`IntelliJ*`、`PyCharm*`），不扫整个 JetBrains 目录 |
| Raycast | 额外扫 VSCode extension storage + 系统级 `/Library/Application Support/*raycast*` |
| DevEco-Studio | 只扫 `~/Library/Caches/Huawei`，保护项目源码/账号令牌/SDK 配置 |

### 2.3 保护层（防误删核心）

四层保护，从最严格到宽松：

**第 1 层 — 系统关键组件（完全禁止卸载）**：

`SYSTEM_CRITICAL_BUNDLES` 列表包含约 80 个 bundle：
- `com.apple.finder`、`com.apple.dock`、`com.apple.Safari`、`com.apple.mail`
- `com.apple.systempreferences`、`com.apple.loginwindow`、`com.apple.controlcenter`
- `com.apple.Settings*`、`com.apple.inputmethod.*`、`com.apple.security*`
- `com.apple.backgroundtaskmanagement*`、`com.apple.sharedfilelist*`
- 以及桌面体验关键组件（通知中心、Spotlight、Mission Control 等）

**第 2 层 — 数据保护应用（卸载模式下可扫描，普通清理模式下保护）**：

`DATA_PROTECTED_BUNDLES` 列表：
- 密码管理器：`com.1password.*`、`com.agilebits.*`、`com.bitwarden.*`、`com.dashlane.*`
- IDE / 编辑器：`com.jetbrains.*`、`com.microsoft.*`、`com.sublimetext.*`
- 代理/VPN：`com.clash.*`、`com.nssurge.*`、`com.v2ray.*`、`com.docker.*`
- 输入法：`com.tencent.*`、`com.sogou.*`、`com.baidu.*`、`im.rime.*`
- AI 工具：Claude、ChatGPT、Codex、Cursor、Ollama 相关 bundle
- 系统服务：`org.cups.*`（打印机配置）、`com.apple.Notes`（用户笔记）

**第 3 层 — 独立 CLI 保护**：

当 `.app` 和独立 CLI 工具共用名时（如 Claude、Codex、Gemini），卸载 GUI 不应删除 CLI 的 XDG dotdir。Mole 通过检查 dotdir 中是否存在独立的可执行文件或 CLI 专属标记来判断，并根据「是否存在对应的 GUI app bundle」决定是否保护。Light Stats 的 Swift 版本可用 `FileManager.fileExists(atPath:)` 检查关键信号文件。

**第 4 层 — 通用词排除**：

以下单词短且常见，不用于 App 名宽泛匹配：

```
Music, Notes, Photos, Finder, Safari, Preview, Calendar, Contacts, Messages,
Reminders, Clock, Weather, Stocks, Books, News, Podcasts, Voice, Files, Store,
System, Helper, Agent, Daemon, Service, Update, Sync, Backup, Cloud,
Manager, Monitor, Server, Client, Worker, Runner, Launcher,
Driver, Plugin, Extension, Widget, Utility
```

### 2.4 Mole 的设计取舍

**明确不做的事**（正确的安全边界）：

| 不做 | 原因 |
|------|------|
| 删除 `~/Documents/`、`~/Desktop/`、`~/Downloads/` | 用户数据，非残留 |
| 删除 `~/Library/Mobile Documents` | iCloud Drive |
| 删除 `~/Library/Keychains`、`~/Library/Accounts`、`~/Library/Mail` | 安全/通信凭据 |
| 删除 CoreAudio 缓存 | 已知会导致 Intel Mac 音频输出丢失 |
| 删除 `~/Library/Caches/com.apple.containermanagerd` | 系统容器管理缓存 |
| 删除 `~/Library/Caches/com.apple.homed` | HomeKit 缓存 |
| 删除音频插件（VST/AU/Components） | 专业音频制作环境依赖 |
| 在 uninstall 模式下自动删除系统级残留 | 标注 review-only，需用户逐一确认 |

---

## 三、Vorssaint 的理念参照

Vorssaint README 把 App 卸载定位为「把 App 拖到 Settings 后扫描 caches、preferences、logs 等残留并移到废纸篓」。
其核心设计要点：

- **Full Disk Access** 只影响扫描完整度，不影响基本功能
- **Finder 自动化权限**在需要时触发（移入废纸篓操作）
- 卸载模型是「扫描 → 展示 → 确认 → 废纸篓」而非静默删除

这与 Light Stats 的「清理」入口语义一致——用户主动操作，结果可见，可撤销（废纸篓）。

---

## 四、对 Light Stats 的建议设计

### 4.1 新增文件结构

```
Light Stats/
├── Services/
│   └── AppUninstallService.swift    ← 新增（actor，纯数据层）
├── Models/
│   └── UninstallModels.swift        ← 新增（InstalledApp, ResidueItem, ScanResult）
├── ViewModels/
│   └── UninstallViewModel.swift     ← 新增（@Observable，协调扫描 + UI 状态）
├── Views/Popover/
│   ├── CleanupTabView.swift         ← 修改（增加 Uninstall 分段）
│   └── Components/
│       ├── AppUninstallRow.swift    ← 新增
│       └── ResiduePreviewSheet.swift ← 新增
```

### 4.2 核心数据模型

```swift
/// 已安装 App 索引条目
struct InstalledApp: Identifiable, Hashable {
    let id = UUID()
    let name: String                // CFBundleName
    let bundlePath: String          // /Applications/X.app
    let bundleId: String?           // com.example.X
    let executableName: String?     // CFBundleExecutable
    let version: String?            // CFBundleShortVersionString
    let isSystemApp: Bool           // com.apple.* 或 /System/Applications/
    let isRunning: Bool
    let icon: NSImage?
    let installDate: Date?          // from bundle directory attributes
}

/// 残留文件/目录类别
enum ResidueCategory: String, CaseIterable {
    case applicationSupport
    case caches
    case logs
    case preferences
    case savedState
    case containers
    case groupContainers
    case webKit
    case httpStorages
    case cookies
    case applicationScripts
    case launchAgents
    case crashReports
    case xdgConfig
}

/// 单条残留
struct ResidueItem: Identifiable {
    let id = UUID()
    let path: String
    let size: UInt64
    let category: ResidueCategory
    let isSystemLevel: Bool
}

/// 扫描结果
struct ScanResult {
    let app: InstalledApp
    let residues: [ResidueItem]
    var totalSize: UInt64 { residues.reduce(0) { $0 + $1.size } }
}
```

### 4.3 扫描算法核心

```swift
actor AppUninstallService {

    /// 主扫描方法：对一个已安装 App 查找所有残留
    func scanResidues(for app: InstalledApp) async -> [ResidueItem] {
        // Step 1: 读 Info.plist 补充信息
        let plist = readInfoPlist(app.bundlePath)

        // Step 2: 校验 bundleId（reverse-DNS 格式）
        let bundleIdValid = isValidReverseDNSBundleId(app.bundleId)

        // Step 3: 生成名称变体集合
        let variants = nameVariants(from: app.name)

        // Step 4: 遍历路径模板，检查文件存在性并计算大小
        var residues: [ResidueItem] = []
        let templates = buildPathTemplates(app: app, variants: variants,
                                            bundleIdValid: bundleIdValid)
        for template in templates {
            guard FileManager.default.fileExists(atPath: template.path) else { continue }
            guard !isSystemCriticalPath(template.path) else { continue }
            guard !isCommonDirectoryRoot(template.path) else { continue }
            let size = directorySize(at: template.path)
            if size > 0 || isFile(template.path) {
                residues.append(ResidueItem(
                    path: template.path,
                    size: size,
                    category: template.category,
                    isSystemLevel: template.path.hasPrefix("/Library/")
                ))
            }
        }

        // Step 5: 应用专项规则（Xcode、VS Code 等）
        residues += applyVendorSpecificRules(for: app)

        return residues
    }
}
```

### 4.4 关键安全函数（Swift 实现）

```swift
/// Reverse-DNS bundle ID 校验
/// Mole 的 `mole_is_reverse_dns_bundle_id` 等价实现
func isValidReverseDNSBundleId(_ id: String?) -> Bool {
    guard let id, !id.isEmpty, id != "unknown" else { return false }
    return id.wholeMatch(
        of: /^[A-Za-z0-9][-A-Za-z0-9]*(\.[A-Za-z0-9][-A-Za-z0-9]*)+$/
    ) != nil
}

/// 通用 App 名排除（Mole 的 `_mole_uninstall_is_common_app_name`）
func isCommonAppName(_ name: String) -> Bool {
    let common = Set([
        "music", "notes", "photos", "finder", "safari", "preview",
        "calendar", "contacts", "messages", "reminders", "clock", "weather",
        "stocks", "books", "news", "podcasts", "voice", "files", "store",
        "system", "helper", "agent", "daemon", "service", "update", "sync",
        "backup", "cloud", "manager", "monitor", "server", "client",
        "worker", "runner", "launcher", "driver", "plugin", "extension",
        "widget", "utility"
    ])
    return common.contains(name.lowercased())
}

/// 系统关键 bundle 判断（基于 Mole SYSTEM_CRITICAL_BUNDLES 精简）
func isProtectedSystemBundle(_ bundleId: String) -> Bool {
    let critical = [
        "com.apple.finder", "com.apple.dock", "com.apple.Safari",
        "com.apple.mail", "com.apple.loginwindow",
        "com.apple.systempreferences", "com.apple.controlcenter",
        "com.apple.Settings", "com.apple.Spotlight",
        "com.apple.notificationcenterui", "com.apple.TextEdit"
    ]
    if critical.contains(where: { bundleId.hasPrefix($0) }) { return true }
    let criticalPatterns = [
        "com.apple.inputmethod.", "com.apple.security",
        "com.apple.backgroundtaskmanagement", "com.apple.sharedfilelist"
    ]
    if criticalPatterns.contains(where: { bundleId.hasPrefix($0) }) { return true }
    return false
}

/// 数据保护 bundle 判断（基于 Mole DATA_PROTECTED_BUNDLES 精简）
func isDataProtectedBundle(_ bundleId: String) -> Bool {
    let protected = [
        "com.1password.", "com.agilebits.", "com.bitwarden.",
        "com.dashlane.", "com.lastpass.",
        "com.jetbrains.", "com.docker.", "org.cups.",
        "com.microsoft.", "com.sublimetext.", "com.sublimehq."
    ]
    return protected.contains(where: { bundleId.hasPrefix($0) })
}
```

### 4.5 安装索引维护

索引是「删除后弹出残留清理」的前提——必须先有索引才能在删除事件发生时查到 bundle_id。

```swift
actor AppUninstallService {
    // 路径 → InstalledApp 映射，持久化到 JSON
    private var installedApps: [String: InstalledApp] = [:]

    /// 启动时全量扫描
    func buildIndex() async {
        let paths = [
            "/Applications",
            "\(NSHomeDirectory())/Applications"
        ]
        for path in paths {
            await enumerateApps(in: path)
        }
        persistIndex()
    }

    /// FSEvents 监听 .app 目录删除
    func startWatching() {
        // 监听 /Applications/ 和 ~/Applications/
        // 检测到 .app 目录删除事件
        // → 在索引中查找被删路径
        // → 找到则触发残留扫描
        // → 弹出清理确认
    }
}
```

### 4.6 删除事件监听方案对比

| 方案 | 优点 | 缺点 | 推荐 |
|------|------|------|------|
| **FSEvents** | 实时、低开销、能拿到被删路径 | 只能拿到路径，需事前索引配合 | ✅ |
| 定期轮询 | 简单 | 延迟大（几分钟），不优雅 | ❌ |

推荐 **FSEvents + 持久化索引** 组合：

```
FSEvents 回调得到被删除的 .app 路径
  → 在 installedApps 索引中查找 (路径 → InstalledApp)
  → 找到 → 自动触发 scanResidues()，弹出 "发现 X 被删除，N 个残留（M MB），是否清理？"
  → 找不到 → 静默忽略（新装的 / 非应用目录的删除）
```

### 4.7 用户交互流程

```
Cleanup Tab
├── [现有] 内存卡片 + 运行中 App 列表（强制退出）
└── [新增] Uninstall 分段
    ├── 已安装 App 列表（按大小/名称排序，含搜索过滤）
    │   └── 每行：图标 + 名称 + 版本 + 总大小 + "扫描残留" 按钮
    ├── 点击扫描 → 展开残留预览
    │   ├── 按类别分组展示文件列表（路径 + 大小 + 勾选框）
    │   ├── 总大小汇总
    │   └── "移到废纸篓" 按钮（默认勾选全部，允许逐项取消）
    ├── 确认弹窗："将 N 个残留项（共 M MB）移入废纸篓？"
    │   └── 确认 → NSWorkspace.recycle() → 操作日志
    └── 自动检测删除弹窗（FSEvents 触发）
        └── "检测到 X 已被删除，发现 N 个残留文件（共 M MB），是否清理？"
```

### 4.8 第一版应保守处理的范围

**应该扫描的（用户级，无需权限）**：

- `~/Library/Application Support/{name}` / `{bundleId}`
- `~/Library/Caches/{name}` / `{bundleId}`
- `~/Library/Logs/{name}` / `{bundleId}`
- `~/Library/Preferences/{name}.plist` / `{bundleId}.plist`
- `~/Library/Saved Application State/{name}.savedState` / `{bundleId}.savedState`
- `~/Library/Containers/{bundleId}`
- `~/Library/WebKit/{bundleId}`
- `~/Library/HTTPStorages/{bundleId}`
- `~/Library/Cookies/{bundleId}.binarycookies`
- `~/Library/Application Scripts/{bundleId}`
- `~/Library/Group Containers/{bundleId}*`（前缀匹配）
- `~/Library/LaunchAgents/{bundleId}.plist` + `{bundleId}.*.plist`
- `~/Library/CrashReporter/{name}_*.plist`

**第一版不扫描的（需 sudo / 高风险）**：

- `/Library/LaunchAgents`、`/Library/LaunchDaemons`
- `/Library/PrivilegedHelperTools`
- `/private/var/db/receipts`
- `/Library/Application Support`

**永远不碰的**：

- `~/Documents`、`~/Desktop`、`~/Downloads`
- `~/Library/Mobile Documents`（iCloud Drive）
- `~/Library/Keychains`、`~/Library/Accounts`、`~/Library/Mail`
- `~/Library/Caches/com.apple.containermanagerd`
- `~/Library/Caches/com.apple.homed`
- `~/Library/Caches/com.apple.coreaudio*`
- 系统关键应用（Finder、Dock、Safari、登录窗口、通知中心等）
- 密码管理器配置目录
- JetBrains IDE 完整配置目录

---

## 五、实施路线

| 阶段 | 内容 | 依赖 |
|------|------|------|
| **P0 — 基础扫描** | `AppUninstallService` actor + 安装索引 + 用户级残留扫描 | 无新依赖，纯 `FileManager` |
| **P1 — UI** | CleanupTab 新增 Uninstall 分段 + 残留预览弹窗 | P0 |
| **P2 — 废纸篓操作** | `NSWorkspace.recycle(_:completionHandler:)` + 操作日志 | P0 |
| **P3 — 自动检测** | FSEvents 监听 .app 目录删除 + 删除后残留清理弹窗 | P0（索引持久化） |
| **P4 — Full Disk Access 提示** | 检测受限目录可访问性，不可读时提示用户开启 | P0 |
| **后续 — 系统级残留** | `/Library/` 路径扫描（review-only，不默认删除） | P0-P2 |

---

## 六、与现有代码的接触面

### 需修改的文件

| 文件 | 改动 |
|------|------|
| `CleanupTabView.swift` | 增加 Uninstall 分段 UI + 状态管理 |
| `SettingsManager.swift` | 新增 `uninstallEnabled` 开关 / 相关 UserDefaults key |
| `en.lproj/Localizable.strings` | 新增约 15 个 uninstall 相关 key |
| `zh-Hans.lproj/Localizable.strings` | 同上，中文本地化 |
| `ja.lproj/Localizable.strings` | 同上，日文本地化 |

### 需新增的文件

| 文件 | 职责 |
|------|------|
| `Services/AppUninstallService.swift` | 核心扫描 actor，索引维护，FSEvents 监听 |
| `Models/UninstallModels.swift` | `InstalledApp`、`ResidueItem`、`ResidueCategory`、`ScanResult` |
| `ViewModels/UninstallViewModel.swift` | `@Observable`，协调扫描状态、UI 绑定、废纸篓操作 |
| `Views/Popover/Components/AppUninstallRow.swift` | 单行 App 列表组件 |
| `Views/Popover/Components/ResiduePreviewSheet.swift` | 残留预览/确认弹窗 |

### 本地化 key 规划

```
// MARK: - Uninstall
"uninstall.title" = "Uninstall";
"uninstall.scan" = "Scan for Leftovers";
"uninstall.scanning" = "Scanning…";
"uninstall.noLeftovers" = "No leftovers found";
"uninstall.leftoversCount" = "%d items (%@)";
"uninstall.moveToTrash" = "Move to Trash";
"uninstall.confirmTitle" = "Move Residues to Trash?";
"uninstall.confirmMessage" = "%d leftover items (%@) will be moved to Trash. You can restore them from Trash if needed.";
"uninstall.moved" = "Moved %d items to Trash";
"uninstall.appDeleted" = "App Removed";
"uninstall.appDeletedMessage" = "\"%@\" was removed. %d leftover items (%@) were found. Clean them up?";
"uninstall.cleanup" = "Clean Up";
"uninstall.ignore" = "Ignore";
"uninstall.installedApps" = "Installed Apps";
"uninstall.category.caches" = "Caches";
"uninstall.category.preferences" = "Preferences";
"uninstall.category.containers" = "Containers";
"uninstall.category.logs" = "Logs";
"uninstall.category.launchAgents" = "Launch Agents";
"uninstall.category.applicationSupport" = "Application Support";
"uninstall.category.other" = "Other";
"uninstall.fullDiskAccessNeeded" = "Full Disk Access needed for complete scan";
```

---

## 七、风险与注意事项

1. **命名相近误匹配**：`app_name` 为 "Code" 时不应匹配到 "Codex" 的目录。Mole 通过精确 bundle_id 匹配 + 短名通用词排除来缓解。Swift 实现应优先使用 bundle_id 精确匹配，仅在 bundle_id 无效时降级到名称变体。

2. **权限不足静默遗漏**：`~/Library/Containers` 某些子目录需要 Full Disk Access，没有权限时 `FileManager.fileExists` 会返回 `false`。应检测并提示用户。

3. **容器内 regenerable 路径**：Containers 下 `Data/Library/Caches` 和 `Data/tmp` 是可安全删除的临时数据，但 Containers 根目录删除可能影响应用沙箱状态。第一版建议先展示 Containers 整目录，后续版本细化。

4. **FSEvents 合并事件**：短时间内大量文件操作会被 FSEvents 合并，需正确处理延迟合并后的路径解析。

5. **废纸篓容量**：`NSWorkspace.recycle()` 对超大文件（如数 GB 的 Caches）可能失败，需处理错误并提示用户手动删除。

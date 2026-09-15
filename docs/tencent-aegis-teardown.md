# 腾讯电脑管家 macOS 版实现拆解（v2）

> 状态：v2 重写（2026-09-14）。对象为本机 `/Applications/腾讯电脑管家.app`，`com.tencent.aegis` 18.2.1.0。
>
> **与 v1 的差异**：v1 是"能借什么 + 为什么不能借"的清单，其中若干条否决理由建立在 `AGENTS.md` 的 *Default form (zero-intrusion)* 冷启动清单与 `PRODUCT.md` 的"零三方依赖 / 无特权 helper / 无遥测"之上。这两份文档已被放宽（冷启动清单整节删除、`zero third-party dependencies`、`No privileged helper`、`No remote telemetry`、`distrust tools that phone home` 均已移除）。**v1 的"不可做"结论因此失效**，本文重做：先把他们每个模块**到底怎么实现**讲清楚，再按当前约束重排取舍，最后给出我们的代码骨架。
>
> **方法边界**：静态拆包。读 `Info.plist` / entitlements / 本地化字符串 / `Resources/` 数据文件 / `otool -L` 链接关系 / `nm -a` 的 ObjC 类名 / `nm -u` 的**导入符号** / `strings -a`。**没有反编译，不复制其代码**。
>
> 标注约定：**事实** = 直接读出的符号、字符串、文件结构；**【推断】** = 由多个事实组合推出的机制；**【未验证】** = 无法从包内证实。

---

## 一、包体与进程拓扑

373 MB，非沙盒。entitlements：`com.apple.developer.system-extension.install`、`com.apple.security.automation.apple-events`、keychain group `FN2V63AD2J.com.tencent.aegis.shared`。

| 进程/组件 | 类型 | 规模 | 职责（事实来源） |
|---|---|---|---|
| `MacOS/腾讯电脑管家` | 主 App | 8.3 MB，**712 个 ObjC 类** | 清理 / 卸载 / 启动项 / 隐私 UI / AI 沙箱 UI / 权限引导 |
| `LoginItems/AEMonitor.app` | LSUIElement 登录项 | 121 MB，**693 个类** | 菜单栏监控 + 长截图 + 网络测速 |
| `LoginItems/AEAgentMonitor.app` | LSUIElement 登录项 | 19 MB，**97 个类** | 隐私访问监控（开机常驻） |
| `LoginItems/AEClawAssistor.app` | LSUIElement 登录项 | 16 MB | AI 沙箱插件宿主 |
| `Frameworks/AEDaemon` | **root LaunchDaemon**（`/Library/LaunchDaemons/com.tencent.aegis.daemon.plist`，`KeepAlive`，`UserName=root`） | 232 KB | 特权删除 / SMC 温度 / kill / launchctl / 包收据 / 更新安装 |
| `SystemExtensions/com.tencent.aegis.fileguard` | **EndpointSecurity 系统扩展**（`SYSX`） | 268 KB | AI 文件访问拦截 |
| `Frameworks/AEUpdater.app` | 独立更新器 | 15 MB | 下载 + 安装 + 重启所有子进程 |
| `Resources/MDCRemote.app` | 远程控制 | 159 MB | 远程协助（与本项目无关） |

私有 framework 分布说明了他们怎么切模块（`otool -L` 事实）：

| Framework | 出现在 | 作用（符号推断） |
|---|---|---|
| `AegisUIKit` | 全部 GUI 进程 | 自己的 UI 基座：`AEBaseWindow/Controller/View`、`AEAlertView`、`AECheckbox`、`AELottieView` |
| `AEShark` | 全部进程 | RPC / 网络 / 配置下发（`RDHttpSession`、`SharkImpl`、`Shiply` 适配） |
| `AEReporter` | 全部进程 | 上报：Bugly 崩溃 + AEShark 通道（`[AEReporter] [AESharkChannel] upload failed: 30s timeout`） |
| `AELogRecall` | 主 App、AEMonitor | 日志收集 → zip → AES-GCM 加密 → 上传 |
| `AEOpenClawKit` | 主 App、AEClawAssistor、AEMonitor | AI agent 产品识别与上下文管理 |
| `AEFileGuardKit` | 主 App、AEClawAssistor | 系统扩展的配置写入与事件读取 |
| `AELongScreenshot` | AEMonitor | 滚动截图拼接 |
| `Taf` | AEMonitor | 腾讯内部通用框架；包内只有壳符号 `PodsDummy_Taf`，**具体能力无法从本包判定**【未验证】 |
| `Lottie` / `Masonry` / `YYModel` / `Protobuf` / `MMKV` / `WCDBObjc` + `sqlcipher` | 多个 | 动画 / 布局 / 建模 / 协议 / KV 存储 / 加密数据库 |

---

## 二、地基：他们所有模块共用的四套基础设施

这一层比功能本身更值得看，因为它是"多进程 + 特权 + 数据驱动"能跑起来的前提。

### 2.1 进程间通信：三套并存，各自有降级

| 通道 | 事实证据 | 用途 |
|---|---|---|
| **XPC（MachService）** | `com.tencent.aegis.daemon`、`…agent-monitor`、`…clawassistor`、`…fileguard.xpc`；`AEDaemon` 导出 `killProcess` / `readCPUTemperature` / `loadLaunchItem` / `unloadAndRemoveLaunchItem` / `enableSystemLaunchItem` / `forgetPackage` / `installAppUpdate` / `getSystemInfoWithReply` | 需要特权的动作、状态同步 |
| **DistributedNotificationCenter** | `com.tencent.aegis.agentsafety.protectionDidChange`、`…configDidChange`、`…vulnScanDidComplete`；`[AEPrivacyDataProvider] posted DNC monitorStateDidChange for all types` | 状态广播（单向通知） |
| **文件事件通道（JSONL）** | `[AgentSafety][EventReader] startMonitoring: path=…, exists=…, mode=…` / `readNewContent:` / `file truncated, reset offset`；`[AEFileGuardReader] entering VNODE watch mode (skipExisting=%d)` / `fallback mode (parentDir VNODE + %gs timer)` | 事件量大或需要审计留痕时，落盘再读，避免 XPC 背压 |

**降级链是显式写死的**：`[AEPrivacyDataProvider] shared database not available, will try XPC fallback` → `XPC not available for sync, relying on shared defaults + DNC` → `XPC unavailable, fallback to local DB`。三种通道互为兜底，任何一个挂掉功能不消失。

### 2.2 调用方校验与完整性保护

- **XPC 客户端按代码签名校验**（`AEDaemon` 导入符号）：`SecCodeCopyGuestWithAttributes` + `kSecGuestAttributeAudit` / `kSecGuestAttributePid` + `SecCodeCheckValidity` + `SecCodeCopySelf` + `kSecCodeInfoTeamIdentifier` + `SecStaticCodeCreateWithPath`。即：root 守护进程不接受任意进程请求，先验证 audit token 对应的进程签名与 Team ID。
- **配置文件 HMAC 保护**：`[FileGuard][ConfigLoader] HMAC …`，配置文件名 `fileguard-config.json` / `file-protection.json` / `es-monitored-processes.json`。
- **上报载荷加密**：`AELogGCMCrypto`（`aegis_log_enc_%@`）+ `AESharkInitializer` 生成并落盘每装机密钥（有 `Failed to open lock file` 的跨进程竞争处理）。
- **更新件校验**：`launchUpdaterAppWithVersion:downloadURL:md5:` → 用 MD5 校验下载件（比我们弱，见 §十）。

### 2.3 存储分层

| 存储 | 事实 | 用途 |
|---|---|---|
| **WCDB + sqlcipher（加密 SQLite）** | `AEPrivacyDatabase`、`AEProtectionLogDatabase`、`[AEPrivacyDataProvider] loaded events from shared WCDB database`、`__wcdb_column_constraint_*` | 跨进程共享的隐私/防护事件库（主 App 只读，监控进程写） |
| **MMKV** | `Shark-MMKV`、`-[MMKV migrateFromUserDefaultsDictionaryRepresentation:]`、`[MMKV mmkvWithID:cryptKey:aes256:rootPath:mode:]` | 偏好与轻量状态（AES256 加密） |
| **Keychain** | `AEMonitor` / `AEClawAssistor` 导入 `kSecClassGenericPassword` 一整套 | 身份凭证 |
| **分散的 SQLite 直读** | `[Cleaner][Privacy][DB] sqlite3_open_v2`、`[Cleaner][Privacy][Safari] History.db`、`visits`、`history_visits` | 浏览器痕迹清理（不复制数据，只查计数与删行） |

### 2.4 规则即数据：加载 → 校验 → 热更新

这是他们整个清理/卸载/防护体系的地基，四要素齐备：

1. **加密封装**：`garbage.enc`、`garbage_en.enc`、`brew_cask_rules.enc`、`browser_privacy_config.enc`、`privacy_config.enc`；日志 `[Cleaner][Parser] Loading %@.enc (decrypted, version=%u)`、`[Uninstaller][Scan] BrewCask rules decrypted (version=%u)`。
2. **版本号**：每个文件都有 `version`（`privacy_default_whitelist.json` 是 `"version": 5`；`claw_uninstall_registry.json` 是 `"version": 1`），解密后回显 version 便于前后兼容。
3. **热更新**：`[FileGuard] Switch config deleted/renamed, re-watching...` / `reloaded %lu rules (config changed)` / `ProcessMatcher loaded %lu rules (from %{public}@, consoleUserHome=%{public}@)` —— 配置文件的 VNODE watcher + 父目录 watcher + 定时器兜底；`[AgentSafety][Plugin] configWatcher:` 同理。
4. **远程覆盖**：`claw_uninstall_registry.json` 的 `description` 明写"支持 Shiply 远程下发覆盖"，日志有 `using remote config map, keys=%lu` / `using remote config string`；域名 `shiply.iot-tencent.com`、`rdelivery.qq.com`、`t.rdelivery.qq.com`。

**安全默认**：规则文件缺失时不是崩溃而是**等待并重试**（`Process config not found, watching parent dir` / `Parent dir not found, will retry later`），加载失败有独立文案（`uninstaller.error.rulesLoad`）。

### 2.5 上报链路

```
业务事件 ──► AEReporter ──┬─► Bugly（崩溃/异常，`ios.bugly.qq.com/rqd/sync`）
                          └─► AESharkChannel（业务埋点，30 s 超时、retCode 判定）
用户点"收集日志" ──► AELogRecall：/Library/Logs/aegis/* + fileguard-status.json
                     ──► /usr/bin/zip ──► AELogGCMCrypto(AES-GCM) ──► AELogUploadAPI
```

还有一条独立的老通道 `rqd.qq.com`（`http://rqd.uu.qq.com/rqd/sync`、`ios.rqd.qq.com/analytics/rqdsync`）。**`reportUpdateWithResult:…competitorInfo:…`** —— 更新结果上报里带竞品安装信息，这条属于不建议借鉴的范畴。

### 2.6 UI 基座

- 自研 `AegisUIKit` 提供窗口/控件/弹窗基类；布局用 Masonry；动画用 Lottie。
- **入场动画是团队约定，且随包发了文档**：`Contents/Resources/NSView+AEEntranceAnimation.md` —— `NSView` 分类，固定 **0.4 s / 80 pt 上移 / EaseInEaseOut**，多组之间固定 **1/6 s** 错开，`ae_playEntranceAnimationWithGroups:` 分组播放，明确要求"**在 Tab 切换时触发，不要放在 `viewDidAppear`**"，并附 `AEPrivacyViewController` 的分组示例。
- **混合开发**：`AEJSBridge` + `ae_bridge.js`（`window.aegisBridge.callNative(api, params, cb)`、事件订阅、`readconfig_int` / `writeconfig_int`、`nativereport`），登录走独立的 `window.webkit.messageHandlers.aegisLoginBridge`；H5 页面托管在 `cdn.m.qq.com/ai_page/…`。桥的失败分支写得很全：`API not found` / `message body is not a dictionary` / `WebView has been deallocated, callback dropped`。

---

## 三、状态栏监控（AEMonitor）—— 与我们产品面重叠最大

### 3.1 为什么做成独立进程

事实：菜单栏宿主是 `Contents/Library/LoginItems/AEMonitor.app`（LSUIElement），由 `SMLoginItemSetEnabled` 注册；主 App 关闭后它继续跑。代价是 121 MB 常驻和一套跨进程状态同步；收益是"监控"与"重 UI"解耦，且菜单栏不会因为主 App 崩溃而消失。

### 3.2 指标采集实现（按导入符号逐条对应）

| 指标 | 他们的实现（`nm -u` 事实） |
|---|---|
| CPU 占用 | `host_statistics64`（`AEMonitor`）+ 进程内缓存 `_cachedCPUUsage` / `_lastCPUUsage` |
| 内存 | `host_statistics64` + `_totalMemoryBytes` / `_usedMemoryBytes` |
| 磁盘容量 | **DiskArbitration**：`DASessionCreate` + `DADiskCreateFromBSDName` + `DADiskCopyDescription` |
| 磁盘/网络吞吐 | 接口计数器差值；另有 `_deviceReadBytesPerSecond` / `_retiredWriteBytesPerSecond` / `_attributedWriteBytesPerSecond` / `_unattributedWriteBytesPerSecond`（**带归因的写带宽**） |
| CPU 温度 | SMC：`IOServiceOpen` + `IOConnectCallStructMethod`；**本地优先，失败走 daemon**（`_readCPUTemperatureLocal` / `_readCPUTemperatureViaDaemon` / `[AEHardwareInfoProvider] XPC call timed out!` / `XPC not available for CPU temp, reconnecting...`） |
| GPU | IORegistry：`IOAccelerator` 相关属性 + `IORegistryEntryCreateCFProperties` / `IORegistryEntrySearchCFProperty` |
| 进程榜 | `proc_listallpids` + `proc_pidinfo` + `proc_pid_rusage`（`proc_pid_rusage` 还能拿到每进程 CPU/能耗，比 `ps` 便宜） |
| 网络可达性 | `SCNetworkReachabilityCreateWithName` + `...SetDispatchQueue` |
| 代理/网络类型 | `[AEMonitor] clientGUID: %@, serverGUID: %@`（走服务端探测） |

温度这条链是反面教材：为了读 SMC 温度，他们给自己造了 "本地读 → XPC 读 → 超时重连 → 不可用" 四级分支维护负担；我们的 `SMCInfo` 在进程内直读 IOKit 就够，**不需要付这个代价**。

### 3.3 状态栏 UI 与刘海

- 单个 `NSStatusItem` + `AEStatusBarView`（`@"AEStatusBarView"`、`@"NSStatusItem"`），显示项由 `statusBarDisplayType` 位掩码控制（`com.tencent.aegis.preference.statusBarDisplayType`）。
- 定位：`_targetXFromStatusBarView:screenFrame:` + `_statusBarDisplayItemCount`。
- 刘海：`_hasNotchScreen`、`safeAreaInsets`、`AENotchAlertTipsView` / `AENotchAlertWindowController` / `_checkNotchTipIfNeeded` / `_showNotchAlert`，一次性提示由 `com.tencent.aegis.preference.notchAlertShown` 记录；文案："您的 Mac 带有刘海屏，开启过多状态栏图标可能导致图标被遮挡不可见。建议仅保留最常用的 1-2 项。"
- 菜单项：`btn_quit_statusbar`、`hideStatusBar`、`monitor.statusBar.tooltip`、`switch_statusbar_info_item_toggle`。

### 3.4 点一下某个进程图标就能关掉它

事实：`[AEMonitor] Close process clicked: name=%@ pid=%d bundleId=%@`，然后三级降级：

1. `[AEMonitor] Daemon kill success (pid=%d, signal=%d)` —— 经 daemon 发信号；
2. `Fallback kill(SIGTERM) sent (pid=%d)` —— 本地 `kill`；
3. `Fallback terminate via bundleId result=%d` / `via runningApps result=%d` —— `NSRunningApplication.terminate()`。

**三级降级 + 每级都记日志**，这是他们所有"动作类"功能的统一写法。

### 3.5 从状态栏推更新

`_showUpdatePromptFromStatusBarWithRetry:` + `[AEMonitor][Update] statusBarView.window not ready after 10 retries, giving up` —— 弹更新提示前先确认 `statusBarView.window` 存在，最多重试 10 次。这是一个真实的坑：**菜单栏进程启动时 window 可能还没挂上**，他们的解法是重试队列而不是延迟写死。

### 3.6 长截图（`AELongScreenshot.framework`）

- 类：`AELongScreenshotManager`、`AELongScreenshotSession`、`AEFrameStitcher`。
- 窗口范围：`getBoundsViaCGWindowListCreateDescription:bounds:`（`CGWindowList` 取目标窗口边界）。
- 拼接：逐帧 + `cumulativeOffset`，失败上报 `reportLongImageGenerateFailWithType:cumulativeOffset:stitchedFrames:`（**失败时带累计偏移和已拼帧数**，便于定位是滚动没触发还是拼接丢帧）。
- 触发：`AEScreenCaptureHotkeyProxy` + 偏好键 `screenCaptureHotkeyKeyCode` / `screenCaptureHotkeyModifiers` / `screenCaptureHotkeyRegistered` / `screenCaptureSaveEnabled` / `screenCaptureSavePath`；跨进程用 `com.tencent.aegis.monitor.triggerScreenCapture` / `…screenCaptureSettingsChanged` 通知。

### 3.7 网络测速（原生实现，不是 H5）

事实（全在 `AEMonitor` 内）：

- 引擎：`AESpeedTestEngine`，方法 `_startDownloadTestWithCompletion:` / `_startUploadTestWithCompletion:`，属性 `_downloadBytesPerSecond` / `_uploadBytesPerSecond` / `_latency` / `_speedTestStartTime` / `_cancelSpeedTest`。
- 下载载荷：`https://webcdn.m.qq.com/speed/SpeedTestData.dat`（自家 CDN 上的固定文件）。
- UI：`AESpeedTestWindow` / `AESpeedTestWindowController` / `AESpeedTestViewController` / `AESpeedTestContentView` / `AESpeedMetricView`，入口来自菜单栏 `monitor.network.speedTest` / `_networkSpeedTestClicked:`。
- 评级：`speedTestRatingOutstanding/Excellent/Good/Pass/NeedsWork` 五档。

### 3.8 登录项注册：三套 API 混用

`[Monitor] registerLoginItem: status BEFORE=%ld` → `SMLoginItemSetEnabled`（legacy，配 `Contents/Library/LoginItems`）→ `status AFTER=%ld, error=%@`；同时读 `SMAppService.status`（`[AELaunchReport] autoStartStatus: SMAppService.status=%ld (0=notRegistered, 1=enabled, 2=requiresApproval, 3=notFound)`）并用 `launchctl list` / `launchctl print` 核对。`syncLoginItemState: showOnBoot=YES, registered` 是他们的真相源同步点。**三套并存是历史包袱**，我们只用 `SMAppService.mainApp` 更干净。

---

## 四、清理（Cleaner）

### 4.1 规则模型：布尔表达式树，不是路径清单

事实（类名 + 描述格式字符串）：

- 层级：`AECleanCategory`（`initWithCategories:filterMap:version:`）→ `AECleanSubItem` / `subCategoryID`（`initWithSubCategoryID:title:tips:bundleID:`）→ `pathItems`。
- 每个 pathItem 带**两棵树**：`pathFilterTree`（是否进入这个目录）与 `actionFilterTree`（进入后哪些条目可清理）。
- 树节点：`AECleanFilterTreeNode`（抽象）/ `AECleanFilterTreeAnd` / `AECleanFilterTreeOr` / `AECleanFilterTreeLeaf`。
- 叶子的实际字段：`<AECleanFilterItem: id=%@, column=%ld, relation=%ld, value=%@, action=%ld>` —— **列 / 关系 / 值 / 动作** 四元组。
- 评估入口：`evaluateCandidateAtPath:name:pathItem:actionFilterTree:pathFilterTree:context:results:`。
- 选择记忆：`recordUserSelectionForSubCategoryID:checked:` + `AECleanSubCategorySelectionsMigrationV2` + `_loadMainAppSubCategorySelections`（对应 UI 那句"下次要按这次的调整来清理吗？"）。

**这就是 `.enc` 里装的东西**：一份可远程更新的、按子类别组织的路径谓词树。它的价值在于**新增一类垃圾 = 加一条规则数据，不用发版**。

### 4.2 扫描器矩阵（`AEClean*Scanner` 类名 + 日志埋点）

| 扫描器 | 实现要点（证据） |
|---|---|
| `AECleanAppCacheScanner` | 应用缓存；`[Cleaner][AppCache][SLOW]` 有慢操作埋点 |
| `AECleanAppLeftoverScanner` | 应用残留 |
| `AECleanBigFileScanner` | **Spotlight 优先**（见 4.3） |
| `AECleanBinaryArchScanner` + `AECleanMachOHelper` + `AECleanArchInfo` | **Mach-O 多架构裁剪**：识别 fat binary 里未使用的架构切片 |
| `AECleanBrokenLaunchScannerImpl` | 失效的 LaunchAgent |
| `AECleanBrokenPlistScanner` | 损坏的 plist |
| `AECleanDirectoryScanner` | 安装包/目录类垃圾（同样 Spotlight 优先：`spotlightInstallPackagesAtPath:` + `discoverInstallPackagesAtRootPath:…usedFallback:`） |
| `AECleanDiskAnalyzer` | 目录体积分析；**符号链接环检测 + 最大深度**（`Symlink cycle detected` / `Max symlink depth reached`） |
| `AECleanDuplicateFileScanner` | 见 4.4 |
| `AECleanSimilarPhotoScanner` | 见 4.5 |
| `AECleanLanguageScannerImpl` | 语言资源文件 |
| `AECleanPrivacyScanner` | 浏览器痕迹（见 4.7） |
| `AECleanTrashScannerImpl` | 废纸篓 |
| `AECleanSoftScannerImpl` / `AECleanWechatScanner` / `AECleanXcodeScannerImpl` | 特定软件（微信、Xcode）的专属规则 |
| `AECleanScannerRegistry` / `AECleanScanCoordinator` / `AECleanSizeCacheManager` / `AECleanSafetyChecker` | 注册表、调度、体积缓存、安全闸 |

### 4.3 大文件/目录扫描：Spotlight 优先 + 自研兜底

事实：`NSMetadataQuery` + 谓词 `kMDItemFSSize > %llu`（还有 `kMDItemPhysicalSize`）+ `/usr/bin/mdutil` 判断索引可用性（`isSpotlightAvailableForPath:`）+ `executeSpotlightQueryForPath:sizeThreshold:context:` + 兜底 `fallbackPathsForScanPath:spotlightPaths:`。

**意义**：全盘遍历很贵，Spotlight 已经把文件大小索引好了；只在索引不可用（外置盘、`.Spotlight-V100` 缺失）时才自己走目录树。这是个可以直接抄的判断——**先问系统有没有现成索引**。

### 4.4 重复文件：三级哈希 + 指纹缓存

事实：`AECleanFileHasher` 同时有 `[Cleaner][FileHasher] md5Hash path=…, fileSize=%llu` 与 `[Cleaner][FileHasher] CRC32 read exception`；导入符号含 `CC_MD5*` / `CC_SHA1*` / `CC_SHA256*`；缓存类 `AECleanFingerprintCache` + `AECleanFingerprintRecord` + `<Fingerprint size=%llu mtime=%.0f>`。

**推断的流水线**：按 (size) 分桶 → 桶内算 CRC32 快筛 → 相同才做 MD5 确认 → 结果按 **(size, mtime)** 缓存，二次扫描直接命中；`AECleanMultiIndexHash` 暗示桶内还有多级索引。

### 4.5 相似照片：感知哈希 + 系统照片库走 AppleScript

事实：`AECleanPerceptualHash`、`[Cleaner][PHash]` 埋点、`AECleanFingerprintCache/Record`（(size, mtime) 缓存）；系统照片库部分 `[Cleaner][SimilarPhoto] hasSystemPhotos: count=%lu, waiting for AppleScript callback`、`AppleScript error/exception`、`performClean: total=%lu, regular=%lu, system=%lu`，清理后在照片 App 里建相册 `AegisCleaner`（`cleaner.similarPhoto.albumName`），放弃删除的走"移到腾讯电脑管家文件夹请手动删除"。

**这就是他们为什么申请「自动化」权限**（`NSAppleEventsUsageDescription` + `AEDeterminePermissionToAutomateTarget` + `AECreateAppleEvent`/`AESendMessage`）：直接操作 Photos 库没有公开 API，他们用 AppleScript。

### 4.6 执行器与安全闸

事实：`AECleanExecutor` / `AECleanExecutorResult` / `AECleanPermissionHelper` / `AECleanSafetyChecker`；日志 `[Cleaner][Executor] Full Disk Access …` / `TCC …` / `Daemon …`；删除走 `trashItemAtURL`（`[Cleaner][SimilarPhoto] trashItemAtURL failed`）；每个阶段有 `[Perf]` / `[SLOW]` 埋点（AppCache、AppLeftover、BinaryArch、BrokenLaunch、BrokenPlist、Executor、Trash 都有）。

### 4.7 浏览器痕迹：注册表 + 三内核实现

事实：`AECleanBrowserRegistry` / `AECleanBrowserConfigLoader` / `AECleanChromiumBaseBrowser` / `AECleanSafariBrowser` / `AECleanFirefoxBrowser` / `AECleanHistoryDatabase` / `AECleanPrivacyDBHelper`；涉及 `cookies.sqlite` / `Login Data` / `Local State` / `Local Storage/leveldb` / Safari `History.db`(`history_visits`) / Firefox `cookies.sqlite`；清理前要求退出浏览器（`AEBrowserQuitAlertView` / `AEBrowserQuitOverlayView`），并要 FDA（`cleaner.privacy.getFullAccess`）。

---

## 五、软件卸载（Uninstaller）

### 5.1 扫描与文件分类

事实：`AEAppScanner` / `AELocalAppScanner`（来源 `Applications` / `Downloads` / `Desktop` / `Documents` / `~/Applications`，对应 `uninstaller.source.*`）；`AEBuiltinUninstallerDetector`（识别自带卸载器的应用）；`AEPkgScanStrategy` + `AEPkgFileNode`。

关联文件被分成 20 类（`uninstaller.fileType.*` 全量表）：程序文件 / 支持文件 / 缓存 / 设置 / 日志 / 沙盒容器 / 共享容器 / Saved State / 崩溃日志 / HTTPStorages / WebKit 数据 / 启动代理 / 启动守护进程 / 启动项 / 内核扩展 / 登录项 / 守护进程项 / 辅助工具 / 卸载脚本 / 文件系统（pkg 收据）。这实际上是一张"**macOS 应用会往哪些位置写东西**"的清单，本身就是可复用的知识。

### 5.2 移除策略矩阵

| 策略类 | 事实证据 | 做法 |
|---|---|---|
| `AEDirectStrategy` | `[Uninstaller][DirectStrategy] canHandleFile NO: unsupported fileType=…` | 直接 `removeItem` |
| `AETrashRemovalStrategy` | `NSFileManager trashItemAtURL failed: … trying Daemon...`、`Daemon moveFilesToTrash timeout` | 优先进废纸篓，失败/超时降级 |
| `AELaunchctlRemovalStrategy` | `launchctl removal: %{public}@, isSystem=%d`、`system launchctl removal succeeded via Daemon` | 先 `launchctl bootout`，系统级走 daemon |
| `AELoginItemRemovalStrategy` | `loginItem removal: …, bundleID=%{public}@` | 撤销登录项注册 |
| `AEKextRemovalStrategy` | `kext removal: unload + delete` | `kextunload` + 删除 |
| `AEPkgScanStrategy` | `[AEDaemon] forgetPackage: %@` | pkg 收据 + `pkgutil --forget` |
| `AEBrewCaskScanStrategy` | `[Uninstaller][Scan] BrewCask rules decrypted (version=%u)` | 用加密规则表识别 cask 安装了哪些文件 |
| 特权路径 | `privileged removal: %@`、`Daemon removal succeeded` → `fallback to authorization` → `authorization removal succeeded` | **daemon → `AuthorizationCreate`（管理员授权弹窗）→ 本地 API** 三级降级 |
| `AEClawUninstallTool` | `primary command succeeded/failed/not found, skip`、`optional command …`、`launchctl labels to bootout: %lu` | 按注册表执行产品专属卸载命令（`openclaw uninstall --all --yes`，再兜 npm/pnpm/bun 全局包） |

### 5.3 安全闸与后置校验

事实（日志原文）：

```
[Uninstaller][Executor] safety check blocked: absolute protected path %{public}@
[Uninstaller][Executor] safety check blocked: container protected path %{public}@
[Uninstaller][Executor] safety check blocked: protected bundleID %{public}@
[Uninstaller][Executor] post-delete verify failed: strategy=%@, path=%@ still exists
```

三道独立闸门（绝对路径 / 沙盒容器路径 / bundle ID）+ 删后校验（文件还在就报失败，而不是当成功）。闸门数据来自 `protected_paths.plist`（critical/protected/caution 三档）与 `protected_bundles.plist`（`com.apple.*`、自身、自身 daemon）。

### 5.4 废纸篓监控与残留提示

事实：`AETrashMonitor` + `FSEventStreamCreate` + 路径 `.Trash` / `~/.Trash` / `/.Trash/` / `/.Trashes/`；`[Uninstaller][TrashMonitor] detected new app in trash: %{public}@`；通知名 `com.tencent.aegis.monitor.trashAppDetected`；体积提醒带"下次提醒时间"（`com.tencent.aegis.monitor.trashSizeNextRemindTime`）；开关 `settings.autoDetectResidual`。

**机制**：FSEvents 监听多个 Trash 路径 → 判定新进废纸篓的是不是 .app bundle → 反查残留 → 弹窗提供一键清理。他们连外置卷的 `/.Trashes/` 都监听了。

### 5.5 Claw 深度卸载注册表

`claw_uninstall_registry.json`（`version` + `description` + `products[]` + `deep_uninstall{primary_commands, optional_commands}`），每个产品声明：`bundle_id_prefixes` / `name_keywords` / `home_dir` / `embedded_detection_paths` / `executable_search_paths` / `is_context_owner` / `enabled`；命令带 `timeout_sec` 与成功/失败文案。另有 `claw_tag_overrides.json` **只做标记不做删除**（能力分离）。

---

## 六、开机启动项（LoginItem）

事实：`AELoginItemManager` / `AELoginItemService` / `AELoginItemApp` / `AELoginItemBase` / `AELoginItemSystem` / `AELoginItemFileCellView` / `AELoginItemOutlineView` / `AELoginItemCacheHelper` / `AELoginItemRemovalStrategy`。

数据源（字符串事实）：

- `Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm` + `scanBTMLoginItemsForApp:addedPaths:results:`（现代 BTM 登录项，**需要 FDA**）
- `scanLaunchAgentsInDirectory:actionFilterTree:context:results:` + `/Library/LaunchAgents` / `legacyLaunchAgentsDirectory`（plist 直读）
- `launchctl list (user) …`、`launchctl list exit=%d`、`Note: Use 'sudo launchctl list | grep aegis' to check system-level services.`

UI 三型（`loginItem.type.appItem/service/system`）、四态筛选（`all/enabled/partialEnabled/disabled`）、"打开文件位置"（`openFileLocation`）。禁用走 `AELoginItemRemovalStrategy`。**注意 `actionFilterTree`**：启动项扫描也复用了 4.1 那套过滤树。

---

## 七、隐私保护（Privacy）

### 7.1 双通道采集

| 通道 | 事实证据 |
|---|---|
| **设备层（谁在用这个设备）** | `AEPrivacyAVDeviceMonitor`；导入 `AudioObjectAddPropertyListenerBlock` / `AudioObjectGetPropertyData` / `AudioObjectRemovePropertyListenerBlock` / `CMIOObjectAddPropertyListenerBlock` / `CMIOObjectGetPropertyData` / `CMIOObjectRemovePropertyListenerBlock`；`watchAllAudioDevices` / `watchAudioDevice:`；日志 `[Privacy][AVDevice] AudioObjectGetPropertyData` / `CMIOObjectGetPropertyData` |
| **事件层（哪个进程申请了权限）** | 统一日志解析，谓词原文：`process == 'coreaudiod' && subsystem == 'com.apple.TCC' && category == 'access'`；`sender == 'replayd' OR sender == 'screencapture' OR sender == 'ScreenCaptureKit' OR sender == 'AVFCapture' OR sender == 'ReplayKit'`；`subsystem == 'com.apple.controlcenter'`；`subsystem == 'com.apple.TCC' AND message CONTAINS 'TCCAccessRequestIndirect: TCCAccessRequestIndirect with pid'`；`service = kTCCServiceMicrophone` / `kTCCServiceSpeaker` / `kTCCServiceAudioOutput`；`process == 'VDCAssistant'` |

**版本化解析器**是这套东西能维护至今的原因（类名事实）：摄像头 `AEPrivacyCameraParser12` / `AEPrivacyCameraParser13`、麦克风 `AEPrivacyMicParser12` / `AEPrivacyMicParser13`、扬声器 `AEPrivacySpeakerParser12` / `AEPrivacySpeakerParser13`、自动化 `AEPrivacyAutomationParser`、屏幕 **`AEPrivacyScreenParser15`**（只有 15 版一个类，正好对应 UI 文案「屏幕信息保护仅支持 macOS 15.0 及以上版本」）。日志格式随系统版本变，他们按版本分解析器，而不是在一个解析器里塞满 `if version >=`。

监控类型 5 种：摄像头 / 麦克风 / 扬声器（系统音频）/ 屏幕 / 自动化。

### 7.2 进程与状态机

- 采集跑在 `AEAgentMonitor`（登录项，开机常驻），写入共享加密库；主 App 通过 XPC 或直接读库（只读）。
- **对账循环**：`[Privacy] reconcileMonitorStates completed: reconciled=%ld` + `reconcile: starting missed monitor type=%ld` / `stopping extra monitor type=%ld` —— 期望状态（设置）与运行状态（监视器实例）定期对账，多起来的停、缺掉的起。`[Privacy][Manager] AEAgentMonitor exiting due to allDisabled` 说明全部关闭时进程自行退出，不空转。
- 事件落库：`[Privacy][DB] insertEvent type=%d isStart=%d` → `[Privacy] insertEvent result=%d eventId=%ld` → 失败才不发 DNC（`[Privacy] DB write failed, skip DNC`，**先落库再广播**，保证 UI 与库一致）。

### 7.3 交互层

- 白名单：`privacy_default_whitelist.json`（v5，默认放行 FaceTime / Photos / Siri 等，按 `watchCamera/Microphone/Screen/Automation/Speaker` 五开关细分），`privacy.whitelist.appType.system/thirdParty` 分类。
- 通知带动作：`本次允许 / 永久允许 / 阻止`（`privacy.notif.actionAllow/AlwaysAllow/Block`），"永久允许"写回白名单。
- 日志页：类型筛选、清空二次确认、`privacy.log.emptyHint`。
- 状态文案分层：`全部监控已开启 / 部分监控已开启 / 监控未开启` + `正在监控 %ld 种设备` + `保护中，暂无访问` + `当前系统不支持（需要 macOS %@ 或更高版本）`。

### 7.4 代价

需要 **完全磁盘访问**（他们整套 `fda.*` 引导文案就是为此），且采集进程必须常驻。这两条现在不再是我们的硬性禁令，但是真实成本：多一个开机进程、多一条权限、多一套"XPC 不可用 → 共享库 → DNC"的降级链。

---

## 八、AI Agent 沙箱与文件保护

这是他们 2026 年的战略重点，也是包内技术含量最高的一块。

### 8.1 产品识别注册表

`AEClawProductRegistry` + `AEClawProductDescriptor` + `AEClawProductRegistryDataSource` + `AEClawRegistryShiplyAdapter` + `AEOpenClawKit`。产品字段（日志原文）：`id / displayName / bundleID / homeDir / configFileName / cliName / iconName / sharesOpenClawContext / isContextOwner / cliMode / detectionMode / requiresConfigValid / enabled / supportsPlugin / esProcessMatchRules`。支持多个 Claw 系产品（openclaw、oneclaw、deskclaw、qclaw、workbuddy…），能处理"多个产品共用一个上下文目录"（`_sharesOpenClawContext`、`_enforceGatewaySingleInstanceForHomeDir:stage:`）。

### 8.2 插件机制（真正的拦截点）

事实：`[AgentSafety][Plugin] installPlugin: bundleResourcePath=%{public}@`、`detectPluginInstallation: plugin=%d (pluginEnabled=YES, registered=%d)`、`manualInstall`、`reinstallPlugin`、`writeInstalledIntent`、`readPluginVersionFromDir:`、`pluginNeedsUpdate:`、`configWatcher:`；插件名 `pcmgr-ai-security`；落地位置 `~/.openclaw/`，注册在 `~/.openclaw/openclaw.json` 与 `openclaw.plugin.json`；调试日志 `~/.openclaw/state/pcmgr-ai-security_debug.log`；安装意图记录在偏好 `com.tencent.aegis.plugin.installed.<product>`。

**机制**：他们不修改 OpenClaw，而是**把插件装进用户的 OpenClaw 环境**，由宿主在 AI 操作的生命周期钩子上回调插件；插件把事件写成文件，原生侧读取。

### 8.3 事件通道与审核

- 读取端：`AEProtectionLogMonitor` + `AEOpenClawEventReader` + `[AgentSafety][EventReader] startMonitoring: path=…, exists=…, source=…, mode=…` / `readNewContent:` / `restartMonitoring: keeping offset=%lld` / `file truncated, reset offset`。**offset 断点续读 + 文件被截断时重置偏移**，这是个容易被忽略的坑，他们明确处理了。
- 事件类型：Prompt / Skills / 脚本执行 / 文件访问（`protectionLogType*`、`operationTypeFromHook:`、`securityModuleForHook:`）。
- 云端判定：`[ProtectionLog][Monitor] skip pending event: hook=%{public}@, requestId=%{public}@`（事件有 pending 态和 requestId）；devTools 文案明写"审核请求域名：`jsonproxy.3g.qq.com` → 正式环境；`jprx.sparta.html5.qq.com` → 测试环境"。**【推断】**：Prompt/Skills/脚本内容会发到腾讯云端做安全判定，返回放行/拦截后落日志。
- 日志页：`风险/安全`、`已拦截/已放行`、`操作类型`、按类型筛选。

### 8.4 文件访问保护（ES 系统扩展）

导入符号（事实）：`es_new_client`、`es_subscribe`、`es_unsubscribe_all`、`es_delete_client`、`es_respond_auth_result`、`es_respond_flags_result`、`es_mute_path_prefix`、`es_mute_process` + `SCDynamicStoreCopyConsoleUser` + `kSecGuestAttributePid` / `kSecCodeInfoIdentifier`。

日志（事实）：`[FileGuard] ES client started successfully` / `authEnabled=YES, subscribed AUTH (%lu events)` / `authEnabled=NO, unsubscribed all events` / `ProcessMatcher initialized: %lu rules` / `[FileGuard] [HealthCheck] file-protection.json`。

配置与热更新（事实）：`fileguard-config.json` / `file-protection.json` / `es-monitored-processes.json`，**HMAC 校验**，`ConfigLoader initialized, path: …, consoleUserHome: …`，`Switch config deleted/renamed, re-watching...`，`Parent dir not found: %@, will retry later`；事件审计输出 JSONL（`[FileGuard] [EventAudit] JSONL`）。

保护模式（UI 事实）：黑名单模式（"AI 不可删改黑名单内文件"）与白名单模式（"AI 仅能删改白名单内文件"）。

**机制总结**：ES AUTH 事件 → `ProcessMatcher` 判定该进程是不是受管 AI agent（规则含 bundle、`app_private_paths`、PPID）→ 命中则 `es_respond_auth_result` 拒绝，并用 `es_respond_flags_result` 改写文件 flags；未开启保护时 `es_unsubscribe_all` 完全退订，不占用内核回调。

### 8.5 漏洞扫描与修复

事实：`_vulnId` / `_riskLevel` / `_affectedVulns` / `_vulnRepairOldVersion` / `_vulnRepairNewVersion` / `GetVulnFileUrl: cmd=%d reqId=%d guid=%{public}@`；类：`AEOpenClawSafetyScanner` / `AEOpenClawSafetyRepairer` / `AEOpenClawVersionUtils` / `AEOpenClawConfiguration`；检测项：本机 AI 应用已知漏洞 / 网络端口暴露 / OpenClaw Gateway 弱口令；修复方式：升级（自动，进度 `已升级 %lu%%`）、改配置、开启端口保护；无法自动修复时给手动步骤（`vulnScan.manual.pwdName = "OpenClaw Gateway 需要设置密码"`）。

漏洞定义文件从服务端按 `guid` 拉取，属于**云端规则**而非内置。

---

## 九、权限引导与失败分型

他们的权限体系有 5+ 条链（FDA / 照片 / 自动化 / 屏幕录制 / 系统扩展），每条的文案结构一致：**做什么 → 去哪 → 找不到条目怎么办**。

代表文案（事实）：

- FDA：`在列表中找到【腾讯电脑管家】-打开【开关】` + `如果列表中没有找到…请点击【+】—选择…—点击【打开】`
- 系统扩展（分版本）：`请在「系统设置 → 隐私与安全性」中批准系统扩展` / `请在「系统设置 → 通用 → 登录与扩展项 → 扩展」中批准系统扩展`
- 落地位置：`应用需要安装在 /Applications 目录下才能开启文件访问保护`
- 失败分型（每条一句人话）：`notPermitted`（缺 FDA）/ `notEntitled`（签名异常）/ `notPrivileged`（扩展未正确加载）/ `internal`（系统安全服务异常，检查 SIP）/ `tooManyClients`（安全软件冲突）/ `unknown`
- 自检恢复：`系统扩展已被禁用/未安装… 请关闭「文件访问保护」功能后重新开启`

---

## 十、自动更新

事实：`AEUpdater.app` 独立进程，由主 App 用 `launchUpdaterAppWithVersion:downloadURL:md5:` 拉起（`[AEUpdaterLauncher] Launching AEUpdater.app with arguments: %@`）；`AEUpdaterDownloader`（`downloader:didUpdateProgress:downloadedBytes:totalBytes:`）+ `AEUpdaterInstaller`；更新信息走自家 RPC（`[AEUpdater] [SharkService] checkUpdate via GetPCTips`）；带**流量计费感知**（`[AEMonitorUpdateChecker] Metered -> unmetered, triggering silent download`）；安装后由 daemon 重启所有子进程（`[AEDaemon] restartRunningSubprocessesForAppUpdate: snapshot monitor=%d agentMonitor=%d clawAssistor=%d` + `some old pids still alive, continue force relaunch`）；结果上报含 `downloadTimeMs` / `checkTimeMs` / `installTimeMs` / `failReason` / `entrance` / `competitorInfo` / `strategyId`。

对比我们：SHA-256 + `codesign --verify --deep` + `spctl --assess` + TeamIdentifier 三重校验，比他们的 MD5 强；但**我们没有"计费网络"判断**，在蜂窝热点上自动下载会白烧流量。

---

## 十一、横向提炼：12 条可复用模式

| # | 模式 | 他们的证据 | 通用价值 |
|---|---|---|---|
| 1 | **规则即数据**：加密封装 + version + 热加载 + 远程覆盖 + 缺失时等待而非崩溃 | `.enc` / `*.json` + `reloaded %lu rules` | 知识会过期，代码不该跟着发版 |
| 2 | **布尔谓词树**（And/Or/Leaf，叶子 = 列/关系/值/动作） | `AECleanFilterTree*`、`<AECleanFilterItem: id, column, relation, value, action>` | 比"路径清单"表达力强一个量级 |
| 3 | **三级降级链**（特权 → 授权 → 本地 API） | Daemon → `AuthorizationCreate` → `NSFileManager`；kill 三级 | 每个动作都要有退路，且每级都记日志 |
| 4 | **删后校验** | `post-delete verify failed: … still exists` | 「命令返回 0」不等于「结果达成」 |
| 5 | **三道安全闸**（绝对路径 / 容器路径 / bundle ID） | `safety check blocked: …` | 破坏性操作要有多重独立否决 |
| 6 | **对账循环**（期望态 vs 运行态，多停缺起） | `reconcileMonitorStates`、`reconcile: starting missed / stopping extra` | 长生命周期状态不要假设迁移一定发生 |
| 7 | **先落库再广播** | `[Privacy] DB write failed, skip DNC` | 广播出去的 UI 状态必须已被持久化 |
| 8 | **Spotlight 优先 + 自研兜底** | `NSMetadataQuery` + `mdutil` + `fallbackPathsForScanPath:` | 能问系统要索引就别自己遍历 |
| 9 | **昂贵计算按 (size, mtime) 缓存** | `AECleanFingerprintRecord` / `<Fingerprint size=%llu mtime=%.0f>` | 哈希/图片特征这类计算的成本控制 |
| 10 | **分级哈希流水线** | size → CRC32 → MD5 | 用便宜的比较尽早淘汰 |
| 11 | **文件事件总线 + offset 断点 + 截断重置** | `[AgentSafety][EventReader] readNewContent` / `file truncated, reset offset` | 跨进程事件量大时比 RPC 稳 |
| 12 | **配置完整性 + 调用方身份** | 配置 HMAC；daemon 用 `SecCodeCheckValidity` 校验 XPC 客户端 | 特权组件只信签名，不信进程 |

---

## 十二、按当前约束重做的取舍

`AGENTS.md` 的 *Default form (zero-intrusion)* 整节已删除，`zero third-party dependencies`、`No privileged helper`、`No remote telemetry` 三句也已移除。下面按**现行**约束重排（✅ 建议做 / ⚠️ 可做但有明确代价 / ❌ 不建议）。

| 能力 | 他们的实现 | 我们的代价 | 判定 |
|---|---|---|---|
| 菜单栏宽度/刘海防护 | `safeAreaInsets` + 一次性提示 | 几乎为零，且修的是我们**现存缺陷** | ✅ 最先做 |
| 规则即数据（含谓词树） | `AECleanFilterTree` + `.enc` | 明文 JSON + 加载器 + 单测 | ✅ 做（**不要**加密、不要远程下发） |
| 三级降级链 | Daemon → Authorization → 本地 | 先只做"本地 + 明确文案" | ✅ 做降级与文案，暂不做特权级 |
| 删后校验 | `post-delete verify failed` | 几行代码 | ✅ 做 |
| 三道安全闸 | `protected_paths.plist` 等 | 一个纯函数 + 单测 | ✅ 做 |
| 对账循环 | `reconcileMonitorStates` | 一个 `reconcile()` + timer | ✅ 做 |
| 启动项只读清单 | BTM + LaunchAgents + launchctl | 解析器 + fixtures | ✅ 做（BTM 段需 FDA，先跳过） |
| 权限文案分版本 + 落地自检 | 5 条权限链 + 失败分型 | 文案表 + `/Applications` 检查 | ✅ 做 |
| 废纸篓体积 | FSEvents + 体积提醒 | 按需测量（可借 #8 Spotlight 思路） | ✅ 做（不引 FSEvents） |
| **计费网络判断** | `Metered -> unmetered, triggering silent download` | `NWPathMonitor.isExpensive` | ✅ 做（小而明确） |
| 网络测速（原生） | `AESpeedTestEngine` + 自家 CDN 载荷 | 新端点 + 隐私政策 | ⚠️ 用户触发即可，端点用我们已有 R2 |
| 隐私访问监控 | CoreAudio/CMIO + 日志谓词 + 常驻进程 + 共享库 | FDA + 第 4 个进程 + 降级链 | ⚠️ 现在允许了，但这是"产品要不要变成隐私工具"的决策，不是技术问题 |
| root 特权 helper | LaunchDaemon + XPC + 签名校验 | 公证流程 + 安装 UX + 卸载残留 | ⚠️ 只在出现"必须特权"的真实需求时做；目前没有 |
| 独立菜单栏宿主进程 | `AEMonitor` 121 MB | 拆进程 + 状态同步 + 两倍内存 | ❌ 我们的单进程 + 单 item 更省 |
| 第三方依赖（Lottie/Masonry/WCDB…） | 157 MB `Library/` | 我们目前零依赖、无 SPM | ⚠️ 只在校验"手写成本确实高"时引入（如本地 DB） |
| 遥测（Bugly/AEShark/rqd） | 全链路 | 隐私政策 + 用户信任成本 | ❌ 现状（无遥测）是我们的差异点，不要在未获明确要求时引入 |
| 加密规则 + Shiply 远程下发 | `.enc` + `rdelivery` | 破坏可审计性 | ❌ |
| 更新结果上报里带 `competitorInfo` | 事实 | — | ❌ 明确不抄 |
| ES 系统扩展做文件保护 | `es_*` 一整套 | 用户批准 + 重启 + 内核级责任 | ❌ 超出"监控"产品范围 |
| H5 混合 UI / JSBridge | `ae_bridge.js` | 我们是原生产品 | ❌ |

---

## 十三、落地实现方案（我们的代码骨架）

沿用现有分层（`Views → ViewModels → Services → Models`，`Utilities` 无 app 知识），纯逻辑必须可单测，四语言本地化同步，`swiftlint lint --strict`（行宽 140 / 函数体 90 行 / 文件 800 行）。

### 13.1 `MenuBarBudget` + `MenuBarGeometry`（刘海与宽度预算）

现状缺陷：`Views/StatusBar/StatusBarView.swift` 的 `calculateWidth(settings:)` 只有 `max(width, 20)` 下限；`AppDelegate.swift` 两处直接把宽度赋给 `statusItem.length`，无预算约束。九项全开约 295 pt。

```swift
// Models/MenuBarBudget.swift —— 宽度真源（从 StatusBarView.Layout 迁出），纯函数
nonisolated enum MenuBarMetric: String, CaseIterable, Sendable {
    case logo, health, cpu, gpu, memory, disk, network, fan, battery
    var width: CGFloat { get }        // logo 16 / health 27 / cpu·gpu·memory 26 / disk 46 / network 56 / fan 22 / battery 34
    var dropRank: Int { get }         // 装饰类 0…3，数据类 4…8（cpu 最后）
}

nonisolated struct MenuBarBudget: Sendable {
    struct Fit: Sendable, Equatable {
        let metrics: [MenuBarMetric]; let compact: Bool; let width: CGFloat
        let dropped: [MenuBarMetric]; let isOverBudget: Bool
    }
    static func width(of metrics: [MenuBarMetric], compact: Bool) -> CGFloat
    static func fit(_ enabled: [MenuBarMetric], budget: CGFloat) -> Fit
}

// Utilities/MenuBarGeometry.swift —— 只看 NSScreen
nonisolated enum MenuBarGeometry {
    /// 纯函数重载：测试直接喂值，NSScreen 版本只是取值转发（避开"UI 不可测"）
    static func hasNotch(safeAreaTop: CGFloat, leftArea: NSRect?, rightArea: NSRect?) -> Bool
    static func hasNotch(on screen: NSScreen) -> Bool
    static func safeLeftBound(for screen: NSScreen) -> CGFloat   // auxiliaryTopRightArea?.minX ?? 0
}
```

接线（复用现有 `updateStatusItem` 路径，不新增定时器）：映射 `settings.showXxx → [MenuBarMetric]` 留在 View 层（`StatusBarView.enabledMetrics(settings:)`），预算与丢弃顺序留在纯函数里；`DispatchQueue.main.async` 之后再读 `button.window?.screen` 做越界检测（首次布局前 `window` 为 `nil`）。

单测 `MenuBarBudgetTests`：全开宽度等于手算常量；差 1 pt 丢 logo；极端不足时 `compact == true` 且**数据指标一个不少**、`isOverBudget == true`；无刘海不得改变指标顺序。

### 13.2 规则数据化 + 谓词树（借 §十一 #1 #2）

- `Resources/AppFilterRules.json`（`schemaVersion` + 条目带 `enabled` / `note`），把 `ViewModels/SystemAppFilter.swift` 里那些**被注释掉的条目**改成 `enabled: false` —— 决策理由终于有了存储位置。
- `Models/AppFilterRules.swift`（`Sendable` + `matchesWatchList`）+ `Services/AppFilterRulesLoader.swift`（失败 → `builtInFallback` + `DiagnosticLogService` 记 `reasonCode`）。**不做** `UsageProviderRegistry` 数据化（descriptor 带闭包，数据化会丢编译期类型安全）。
- 若将来规则复杂度上升（多条件、按类型组合），再引入 `FilterTree{ And, Or, Leaf(column, relation, value, action) }` 这一层；现在只有"路径 + 通配"需求，先用扁平结构。
- 单测：解码真实 bundle 资源（防漂移，参考 `FinderMenuTemplateTests`）、`enabled: false` 不命中、`schemaVersion` 高于已知 → 兜底。

### 13.3 `ProtectedPathPolicy`（借 #4 #5）

`Resources/ProtectedPaths.plist`（`version` + `critical` / `protected` / `caution` + `protectedBundleIds`）+ `Models/ProtectedPathPolicy.swift`：

```swift
nonisolated struct ProtectedPathPolicy: Sendable {
    static let `default`: ProtectedPathPolicy            // 资源缺失时的保守兜底
    func tier(forPath: String) -> ProtectionTier         // prefix 边界：== 或 hasPrefix(rule + "/")
    func tier(forBundleId bundleId: String?) -> ProtectionTier
    func allowsRemoval(path: String, bundleId: String?, userConfirmed: Bool) -> Bool
}
```

接线：`AppMemoryManager` 终止前判定（Finder / Dock / SystemUIServer / 自身恒为 critical）；`Services/FinderMenuFileService.swift` 的 `transfer(paths:to:move:)` 对**源**做 tier 检查（当前完全无分级，`moveItem` 也非废纸篓）；错误文案区分"受系统保护"与"权限不足"。

单测：`/Library` 不匹配 `/LibraryFoo`；`/etc`→`/private/etc` 因 `/private` 为 critical 而判 critical（**有意的过度保护**，写进注释与测试）；`com.apple.*` 按 `.` 边界匹配。

### 13.4 `LoginItemParser`（只读清单）

`Models/LoginItem.swift` + `Services/LoginItemParser.swift`（纯解析：plist → `ProgramArguments[0]` → `Program` → `BundleProgram` 回退；`launchctl list` 的 `-` 容忍；`owningApp(forProgramPath:)` 向上找最近 `.app`）+ `Services/LoginItemInventoryService.swift`（`actor`，目录扫描 + TTL 缓存）。**只读**，禁用不做；UI 明示"BTM 托管项（含 Light Stats 自身）不在列表"，并显式注入自身那一行。

### 13.5 `TrashUsageService`（借 #8）

```swift
nonisolated enum TrashUsageService {
    struct Usage: Sendable, Equatable { let bytes: UInt64; let isPartial: Bool }
    static func measure(at url: URL, entryLimit: Int = 200_000, timeBudget: TimeInterval = 0.15) -> Usage
}
```

`FileManager.enumerator` + `.totalFileAllocatedSizeKey`（回退 `fileAllocatedSize` → `fileSize`），不跟随符号链接，超预算返回 `isPartial`（UI 显示 `≥`）。**不进 `MonitorSampler.collect()`**，只在面板打开时按需 + 30 s TTL。若废纸篓条目数极大，可先试 `NSMetadataQuery`（Spotlight 覆盖 `~/.Trash` 时）再兜底遍历——这正是他们 `AECleanBigFileScanner` 的思路。

### 13.6 计费网络判断（借 §十）

`Services/UpdateService.swift` 的 `download(_:onProgress:)` 目前直接 `session.bytes(from:)`，全仓无 `NWPathMonitor` / `isExpensive`。加一层：`NWPathMonitor` 判定 `isExpensive || isConstrained` → 自动检查/自动下载时跳过并提示"当前为计费网络"，用户手动触发时照常。单测把"是否允许自动下载"抽成纯函数 `UpdateNetworkPolicy.shouldAutoDownload(path:)`。

### 13.7 对账循环（借 #6）

适用对象：`ScrollDirectionService` / `DefaultInputSourceService` / `DisplayControlManager` / `FindMouseCoordinator` —— 这些服务都持有"开关状态 ↔ 运行状态"两套真相。加一个统一的 `reconcile()`：由 `didWakeNotification` + 低频 timer 触发，期望态来自 `SettingsManager`，多停缺起，并记 `DiagnosticLogService`（`reasonCode` 区分"缺失"与"多余"）。

### 13.8 权限文案表（借 §九）

`Models/PermissionGuide.swift`（`steps(for:version:)` + `settingsURL(for:)`）+ `Utilities/BundleLocation.swift`（当前副本不在 `/Applications` 且已存在安装副本 → 警告；纯本地开发不打扰）。只写我们亲手在对应系统版本上确认过的路径；表是数据，未来版本 = 改表 + 加断言。

---

## 十四、路线图

| 阶段 | 内容 | 验收 |
|---|---|---|
| **M0** | 13.1 刘海/宽度预算；13.8 权限文案表 | `MenuBarBudgetTests` / `PermissionGuideTests` 全绿；有刘海机器上 `button.window.frame.minX >= safeLeftBound` |
| **M1** | 13.2 规则数据化（`SystemAppFilter` → JSON + 谓词结构预留） | 原 `SystemAppFilterTests` 4 条不改仍过；新增解码/兜底/前向兼容用例 |
| **M2** | 13.3 分级保护 + 删后校验；13.6 计费网络 | `ProtectedPathPolicyTests`、`UpdateNetworkPolicyTests`；Finder 与自身进程不可结束 |
| **M3** | 13.4 启动项只读清单 | `LoginItemParserTests`；与 `launchctl list` 人工比对一致 |
| **M4** | 13.5 废纸篓体积；13.7 对账循环 | `TrashUsageServiceTests`；采样耗时无回归 |
| **M5（需拍板）** | 隐私监控 / 网络测速 / 特权 helper / 第三方依赖 | 逐项单独评审 |

每阶段结束跑 `./script/test.sh` 与 `swiftlint lint --strict`；新增 `Resources/` 文件要同步 `AGENTS.md` / `CLAUDE.md` 的 Layout 段（两文件互为镜像）。

---

## 十五、复现命令

```bash
APP="/Applications/腾讯电脑管家.app"

# 本地化（UTF-16 → UTF-8）
iconv -f UTF-16 -t UTF-8 "$APP/Contents/Resources/zh-Hans.lproj/Localizable.strings" > /tmp/zh.strings

# 链接关系与权限
otool -L "$APP/Contents/MacOS/腾讯电脑管家"
codesign -d --entitlements - "$APP/Contents/MacOS/腾讯电脑管家"

# 类名普查（模块地图）
nm -a "$APP/Contents/MacOS/腾讯电脑管家" | grep -oE '_OBJC_CLASS_\$_[A-Za-z0-9_]+' | sed 's/.*\$_//' | sort -u > /tmp/classes.txt

# 导入符号（= 他们到底调了哪些系统 API）
nm -u "$APP/Contents/Library/LoginItems/AEMonitor.app/Contents/MacOS/AEMonitor"

# 把全包字符串汇总后按模块检索（本文主要情报源）
find "$APP/Contents" -type f -perm +111 -not -path "*/_CodeSignature/*" \
  -not -path "*/Resources/MDCRemote.app/*" | while read -r f; do
    echo "@@@FILE ${f#$APP/}"; strings -a "$f"
  done > /tmp/all.txt
grep -aE '\[FileGuard\]|\[Cleaner\]|\[Uninstaller\]|\[Privacy\]' /tmp/all.txt | sort -u
```

---

## 附：本文未采纳/未证的项

- 隐私事件的**云端审核**结论标为【推断】（依据：devTools 文案明确提到"审核请求域名"、`requestId` 与 `pending` 态事件、`jsonproxy.3g.qq.com` 域名），未做抓包验证。
- 重复文件流水线的 CRC32 → MD5 顺序为**【推断】**（依据：`AECleanFileHasher` 同时只有这两条日志路径 + `AECleanMultiIndexHash` 类名）。
- `backgrounditems.btm` 是否需要 FDA 为**【推断】**（他们本身申请 FDA，无法单独判定）。
- 长截图的帧来源（是 `CGWindowList` 逐帧抓取还是 ScreenCaptureKit）只证到 `getBoundsViaCGWindowListCreateDescription:bounds:` 与 `AEFrameStitcher`，未证到具体抓帧 API。

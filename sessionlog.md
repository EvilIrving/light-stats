## 滚动反转全系统死机修复 + 水平反转/步长倍率扩展 · 2026-06-20 02:05 · claude-opus-4-8

新功能 `ScrollDirectionService`（鼠标滚轮方向反转）开启后，一滚动整台电脑就卡死，触控板也连带卡。

**根因（架构性，非笔误）**：tap 是 `.cgSessionEventTap` + `.defaultTap` —— 会话级「主动」同步 tap，WindowServer 会**同步等待回调返回**才把滚动事件派发给任何 App。原代码把 run loop source 挂在 `CFRunLoopGetCurrent()` = **主 RunLoop**（`start()` 由 `@MainActor` AppDelegate 调用）。而本 app 主线程每秒被 `SystemMonitor` 的 `proc_listallpids`+逐进程 `task_info` 阻塞几十~几百 ms，期间 tap 得不到服务 → WindowServer 卡住全系统滚动输入。卡的是**事件派发链路**不是翻转逻辑，所以只翻鼠标 delta 却连触控板一起卡。`KeyboardLockService` 用同样主线程模式没事，是因为它只在 60s 清洁模式短暂存在；**常驻 tap 绝不能共用繁忙主 RunLoop**。

**修法**：tap 移到专用 `Thread`（`.userInteractive`）跑自己的 `CFRunLoop`，与主线程监控负载彻底解耦（Scroll Reverser / Mac Mouse Fix 的标准架构）。跨线程状态用 `NSLock` 守护，`while isRunning` + `CFRunLoopStop` 兜住「刚 start 又 stop」竞态，确保关开关时 tap 一定被 disable（否则会「关了还在反转」）。权限先在主线程同步 `AXIsProcessTrusted` 检查，避免后台线程才发现失败还要跨线程回传。

**随后按用户要求扩展**（先被要求删 popover 顶栏的冗余反转图标，只留设置入口；再要求补齐水平反转 + 阻尼）：
- 配置驱动：新增 `ScrollConfig{reverseVertical, reverseHorizontal, stepMultiplier}`，`stateLock` 守护 + `updateConfig()` 热更新（改倍率不重启 tap）。`handle()` 对 Axis1/Axis2 各自独立施加「翻转×倍率」，每轴处理三个 delta 字段（整数行/定点数/点数）。整数行步进 `keepDirectionFloor`：低倍率舍入到 0 但原值非 0 时保留结果方向 ±1，否则按行滚动的 App 在 0.25× 完全滚不动。
- 用户拍板的三个决策：水平反转=**独立开关**；阻尼=**步长倍率 0.25×–3×**默认 1×作用于双轴；**阻尼依附反转开关**（tap 仅在 `垂直∨水平反转` 开启时运行，单独调倍率不启动 tap，设置里滑块在两反转都关时禁用+淡化）。
- AppDelegate `syncScrollService()` 监听三个偏好任一变更 → 推配置 + 按 `垂直∨水平` 决定起停。

**坑**：`CFMachPortCreateRunLoopSource` 返回 optional 要解包。仅作用于 `!isContinuous`（传统鼠标滚轮），触控板/Magic Mouse 直通——若日后要让 Magic Mouse 也反转需另判（它走连续滚动，当前归为「自然」）。**无法在本机验证死机是否真消除**——需用户开开关+授权辅助功能后亲手滚动确认。全程 `swiftlint --strict` 0 违规、`validate_localization.sh` 151 键 ×4 语言全覆盖、debug-run 构建通过。

---

## 修复 Claude 用量隔夜必失败：token 被永久缓存死 + 401 跳过降级 · 2026-06-19 12:09 · claude-opus-4-8

**现象**：Claude 用量「放着不动，第二天必显示获取失败」，定时器的自动重试从来不成功，只有重启 app 或手动重置缓存才恢复。Codex（read-only）独立核过根因与修法。

**根因（两个叠加）**：
1. OAuth access token 只活几小时（凭证 JSON 里 `claudeAiOauth.expiresAt` 是毫秒 epoch，实测约 3h 窗口）。CLI 会用 refreshToken 刷新并写回 Keychain，但 `ClaudeUsageService` 把 token 进程级永久缓存在 `_cachedToken`，只有手动 `resetCredentialCache()` 才清。菜单栏 app 常驻数天 → 一直喂死 token → 永久 401。
2. `fetch()` 收到 `.tokenExpired` 直接 `throw`，**跳过了写好的 Messages API + CLI-PTY 三层降级**。而 CLI-PTY 兜底恰恰会启动 `claude`、读 CLI 自己刚刷新的凭证——是唯一不依赖那个死 token 的真·恢复路径，却在最该用的时候被绕过。因果接反了：`.tokenExpired` 本该是触发降级的头号信号，却被当成终止降级的开关。

对照组：`CodexUsageService` 一直是对的（每次现读凭证、401→重读比对→重试一次→CLI 兜底）。6/17 给 Claude 堆三层降级时，唯独漏了 Codex 早验证过的这个环节。

**修法**：
- `ClaudeUsageService.fetch()` 的 `.tokenExpired` 改为 `recoverFromExpiredToken()`：失效缓存→重读→token 真变了重试 API 一次→否则走 CLI-PTY。不再拿已知过期 token 白敲 Messages API。
- token 缓存换成 `ClaudeTokenCache` actor（消除静态可变缓存的数据竞争），存 `token + expiresAt`，过期前 60s 自动失效。**保留 401 强制失效**——截断凭证/缺 expiresAt/提前吊销靠时间判断不出来，两道机制并存。
- `AIUsageMonitor.handle()`：`tokenExpired` 有旧快照时走 `.stale` 而非 `.error`，不再一过期就甩红脸；仅 `.credentialsMissing`（登出）才报错。
- Gemini 同类轻症（每次现读、无永久缓存，但早 401 不强制刷新）：`fetch()` catch `.tokenExpired` → `forceRefreshAccessToken()` 绕过过期时钟强制刷新重试一次。

**注意的坑**：
- `type_body_length` 限 500（CLAUDE.md 写的 800 是 file_length，别混）。`CachedCredential`/`ClaudeTokenCache`/`parseClaudeCredential`/`parseClaudeExpiry` 都移到了文件作用域（私有顶层，紧耦合 helper 豁免），就是为了把行数移出 enum body。
- 弹窗安全：恢复路径坚持「先读文件 + `/usr/bin/security` 子进程」，不碰会弹授权框的 `SecItemCopyMatching`，不会把之前消掉的 Keychain 弹窗带回来。
- **没法在本机验证隔夜恢复**——要等真实 token 过期才触发。逻辑链已双人核过，但最终判据是装新版放一夜看次日能否自愈。
- 顺手修了 `AIUsageCard.swift:201` 一个预存的 `p` 变量名 lint 红线（改 `vertex`，197 行已占 `point`）——它之前就 commit 进去了，main 的 strict lint 本来是红的。

构建 BUILD SUCCEEDED，全项目 `swiftlint --strict` 0 违规。

---

## 修复状态栏弹窗不显示：NSPanel canBecomeKey · 2026-06-07 11:13 · claude-opus-4-8

点击状态栏图标无弹窗，控制台刷 `makeKeyWindow … canBecomeKeyWindow NO` 警告。

**根因**：`AppDelegate.setupPanel()` 的 `NSPanel` 用了无标题栏样式 `[.nonactivatingPanel, .fullSizeContentView]`，此类面板默认 `canBecomeKey` 返回 false。导致 `makeKeyAndOrderFront` 拿不到 key 状态（报警告），又因 `hidesOnDeactivate = true`，`NSApp.activate` 触发的失活流程立刻把面板 `orderOut` 隐藏 → 表现为"没弹窗"。

**修法**：新增 `KeyablePanel: NSPanel` 子类重写 `canBecomeKey`/`canBecomeMain` 返回 true，`setupPanel()` 改用 `KeyablePanel(...)`。

控制台开头的 `GenerativeModelsAvailability` / `AFIsDeviceGreymatterEligible Missing entitlements` 是系统 Apple Intelligence 日志噪音，与此 bug 无关。

---

## Light Stats（macos-menus-stats）：打包 · 签名 · 公证全流程与 Secrets · 2026-05-03 · composer

以下按 `**.github/workflows/release.yml**`、`**build.sh**` 写清：**打 tag → CI → DMG → GitHub Release** 各环节做什么，以及 `**Issuer ID`**（口述常误说成 **Issue ID**）、**Key ID**、**.p12**、**.p8** 分别对应哪些 Secret。**Job 使用 `environment: APPLE`**，敏感项集中在 **Settings → Environments → APPLE**；`**GITHUB_TOKEN`** 仅由 Actions 自动注入 `action-gh-release`，不必手动配置。

**时间顺序（与 workflow steps 对齐）**：Checkout，从 `**refs/tags/v*`** 去前缀得到 `**VERSION**` → `**Import Code Signing Certificate**`：`BUILD_CERTIFICATE_BASE64` `**base64 --decode**` → `certificate.p12`，用 `**KEYCHAIN_PASSWORD**` 建/解锁 `**$RUNNER_TEMP/app-signing.keychain-db**`，`security import … -P "$P12_PASSWORD"`，再 `**find-identity**` 断言存在 `**Developer ID Application**` → `**build.sh**` → `**Verify Notarization**`（`spctl`、`stapler validate`）→ changelog → `**softprops/action-gh-release**` 上传 `**build/output/*.dmg**`。

---

### `build.sh` 流水线（源码级）

公证是否开启：仅当 `**APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`、`APPLE_API_KEY_BASE64` 皆非空**，`NOTARIZATION_ENABLED=1`；否则跳过 **notarytool / stapler**（当前 `**release.yml` 仍跑 verify**，故正式发版三项 API Secret 应收齐）。

- **开发者身份**：`security find-identity -v -p codesigning` 取 `**Developer ID Application: …`** 首部匹配串作 `**codesign --sign**`；环境变量 `**DEVELOPER_ID**` 可手写完整字符串盖过自动解析。
- **编译**：`xcodebuild build` 使用 `**CODE_SIGNING_ALLOWED=NO`** 等，先得到 **未签名** Release `**Light Stats.app`**，避免与 CI 导入的 Developer ID 抢签名。
- **复制**：`build/output/Light Stats.app`
- **签应用**：`codesign`：`--deep --force`、`--options runtime`、`Light Stats/LightStats.entitlements`、`--timestamp`、`--sign "$DEVELOPER_ID"`；自检 Hardened Runtime 与时间戳。
- **打包 DMG**：`hdiutil create` → `build/output/Light Stats-<VERSION>.dmg`
- **签 DMG**：再次对该 DMG 执行 `codesign`
- **公证**：解码 `APPLE_API_KEY_BASE64` → `build/api-key.p8`（`chmod 600`）；`xcrun notarytool submit … --wait`，传入 `--key-id "$APPLE_API_KEY_ID"`、`--issuer "$APPLE_API_ISSUER_ID"`、`--key` 指向该 `.p8`；成功后 `stapler staple`

---

### Secrets 与环境变量一览（本项目 Release job）


| Secret                         | workflow 别名                | 作用                                                                              |
| ------------------------------ | -------------------------- | ------------------------------------------------------------------------------- |
| `**BUILD_CERTIFICATE_BASE64`** | `secrets.CSC_LINK`         | Developer ID `.p12` Base64；job 内 pipe 至 `base64 --decode` 再 `security import`。  |
| `**P12_PASSWORD**`             | `secrets.CSC_KEY_PASSWORD` | 导出 P12 时密码。                                                                     |
| `**KEYCHAIN_PASSWORD**`        | （无别名）                      | 仅锁住 Runner **新建的临时钥匙串**；与 Apple 账号无关，自设强密码即可。                                   |
| `**APPLE_API_KEY_ID`**         | —                          | **Key ID**；与 `**AuthKey_<Key ID>.p8`** 文件名中 ID 一致；传给 `**notarytool --key-id**`。 |
| `**APPLE_API_ISSUER_ID**`      | —                          | **Issuer ID**（控制台上的 **UUID**，不是「Issue ID」）；传给 `**notarytool --issuer`**。        |
| `**APPLE_API_KEY_BASE64**`     | —                          | `**AuthKey_*.p8` 全文 Base64**；脚本解码为 `**$BUILD_DIR/api-key.p8`**。                 |


**从何而来 · Base64：** **Developer ID**：在 developer.apple.com 创建 **Developer ID Application（G2）** → 钥匙串导出 `.p12` → `base64 -i Your.p12 | pbcopy` → 填入 `BUILD_CERTIFICATE_BASE64`。**公证 API**：在 App Store Connect →「用户与访问」→「密钥」复制页顶 **Issuer ID**，新建密钥记下 **Key ID**，下载 `**.p8`（仅能下载一次）** → `base64 -i AuthKey_XXXXXXXX.p8 | pbcopy`。若 CI 解码失败，可对 P12 / p8 先 `tr -d '\n'` 压成单行再贴 Secret。

**可选覆盖：** Actions 环境里设 `**DEVELOPER_ID=Developer ID Application: 全名`**，避免多台机器 `**find-identity` 文言差异**。

---

### 与同文件下文的关系

- **操作级细节**（CSR、菜单栏证书助理、双击 `.cer`、Development 与 Developer ID 混用的 exit 1）：下一节 **GitHub Release 签名失败：Development 证书 vs Developer ID**。
- **xcodebuild 日志与 Xcode 版本差**：后部 **build.sh 增加错误日志透出**。
- `**release.yml`** 与 `**build.sh**` 若改版，本节应随之修订。

---

## GitHub Release 签名失败：Development 证书 vs Developer ID · 2026-05-03 · composer

### 现象与错误

- CI（`release.yml`「Import Code Signing Certificate」）在证书已成功导入后出现 **Process completed with exit code 1**。
- 日志：`security import` 成功（`1 identity imported`）；`security find-identity -v -p codesigning` 仅列出 **Apple Development: …**。
- 流水线里若用 `grep "Developer ID Application"` 做断言：**无匹配时 `grep` 退出码为 1**，整条 `run:` 失败，容易误判为「Secret 丢了」——实为**类型不匹配**。

### 根因

- `**BUILD_CERTIFICATE_BASE64`** 解压出的 P12 若是 Apple Development，只能覆盖开发/Debug 场景；当前 Release 流水线要的是：**DMG 用 Developer ID Application 签名 + 公证**，`build.sh` 也是从 keychain 里取 **Developer ID Application**。
- Secret 若在 Environment `APPLE` 里且 job 挂了 `environment: APPLE`，则能成功导入则说明 **三类 Secret 都已注入**；失败应优先核对 **Identity 字符串是否含 Developer ID Application**，而不是先怀疑密钥名写错。

### 思路整理：外向分发签字在整条链上卡在哪

先从**目标**想：本项目 Release 流水线要做的是 GitHub 上放出 **DMG**、并由脚本用 **Developer ID** 签名再送 **公证**。这条路径和 Xcode 默认帮你管的 **Apple Development**（调试、真机）不是同一条：**付费账号只是能申请多种证书的门票**，不会让钥匙串里「自动长出」Developer ID；Secret 齐全也只能保证「有东西导入」，不能保证「导入的是哪一种身份」。因此日志里最常见的是：import 成功、`find-identity` 却只列 Development，`grep Developer ID Application` 直接以 exit 1 结束——容易被误读成密钥没配对，实际是**流水线断言的身份字符串与 P12 内容不一致**。

在 Apple 开发者网站选类型时，**Software** 里和「商店外可分发的 Mac App」对齐的是 **Developer ID Application**；**Mac App Distribution / Mac Installer Distribution** 走向 Mac App Store；**Apple Development** 仍停留在开发线。同一页里往往还有 **Services**（推送、Wallet、Apple Pay 等），它们和「给 .app 做代码签名」无关，只是界面挨在一起，容易分心——思路是：**只盯 Software 里与「分发方式」对应的那一条**。

申请证书时网页会要 **CSR**。CSR 只是本机生成的一段请求数据，**不自带「这是 Development 还是 Developer ID」标签**；真正决定证书种类的是你在门户里点的模板。生成 CSR 要用 **钥匙串访问** 里的 **证书助理**，但很多人第一次会满窗口找按钮——**证书助理不在钥匙串窗口内部**，而在 **屏幕最顶部的系统菜单栏**：先让「钥匙串访问」成为当前前台应用，再点 **「钥匙串访问」**（应用名菜单，紧挨左上角苹果菜单的右侧）→ **「证书助理」** → **「从证书颁发机构请求证书…」**（英文系统：**Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority…**）。若出现 **G2 Sub-CA / Previous Sub-CA**，对当前 GitHub `macos-latest` 与常见 Xcode 选 **G2** 即可；Previous 留给必须兼容很老签名链的场景。

证书签发后你会从网站下载 `**.cer` 文件**。安装不需要手搓命令：在访达里 **双击 `.cer`**，系统会走钥匙串导入流程，一般进 **「登录」** 钥匙串。装好后打开钥匙串访问，切到 **「我的证书」**：应看到 **Developer ID Application: …** 这一行，且左侧可展开，下面挂着 **专用密钥**。若只有证书没有私钥，说明 CSR 不是在这台机器上生成的，或私钥丢在别的用户/钥匙串里，**这种证书无法导出成能用于 CI 的 P12**。

GitHub Runner 拿不到你笔记本的登录钥匙串，所以要把 **证书 + 私钥** 打成 `.p12` 再经 Secret 注入。导出：在「我的证书」里选中 **Developer ID Application** 那一整行（含下面折叠的密钥），菜单 **「文件」→「导出项目…」**（或右键），文件格式选 **「个人信息交换 (.p12)」**，为导出文件设一个密码——此密码即 GitHub 的 `**P12_PASSWORD`**。`**KEYCHAIN_PASSWORD**` 则是 CI 里临时创建的钥匙串解锁密码，可以和 Apple 账号或 P12 密码不同，只要和工作流里写的一致即可。

把 `.p12` 写进 Secret 时，仓库里用的是 **Base64 文本**（避免二进制直接粘贴）。在 Mac 终端里，把文件编码进剪贴板常用：

```bash
base64 -i /path/to/DeveloperID.p12 | pbcopy
```

然后把剪贴板整段粘贴到 Secret `**BUILD_CERTIFICATE_BASE64**`。若不想用 `pbcopy`，也可以：

```bash
base64 -i /path/to/DeveloperID.p12
```

把终端打印出的**整段**（含换行与否视平台；GitHub Secret 通常接受单行，可把输出里的换行删掉或一行复制）粘进 Secret。若粘贴后 CI 解码异常，可先压成单行再存 Secret：`base64 -i /path/to/DeveloperID.p12 | tr -d '\n' | pbcopy`。Workflow 里会用 `base64 --decode` 还原成二进制再 `security import`。

`.p12` 内含私钥：谁同时拿到 Secret 文本与密码，谁就能以你的 Developer ID 名义签名。**Environment 权限、分支保护、强密码与 2FA** 是基本要求；怀疑泄露须在 Apple 后台**吊销**该 Developer ID 证书并换新 P12。**若坚持私钥不出本机**，只能改为自托管 Mac 在本地钥匙串完成签名（与当前「上传 base64」模式是另一条运维路线）。

最后把 **思路收束到仓库**：`.github/workflows/release.yml` 负责导入并应能区分「没配 Secret」和「配了但没有 Developer ID 身份」；`build.sh` 在开启公证 API 环境变量时，会从 keychain 解析 **Developer ID Application** 用于 `codesign`。本地自检可执行 `security find-identity -v -p codesigning`，确认列表里出现 **Developer ID Application:** 再推 tag 跑 Release。

### 解决：执行步骤（按顺序、可照做）

**A. 在 Apple 开发者网站创建 Developer ID Application**

- 打开 [Certificates 列表](https://developer.apple.com/account/resources/certificates/list)，点 **+**。
- 选 **Software** → **Developer ID Application**（不要进 Services）。
- **Profile Type** 选 **G2 Sub-CA (Xcode 11.4.1 or later)**，Continue。

**B. 在本机用证书助理生成 CSR（菜单在屏幕最上方，不在钥匙串窗口里）**

- 打开 **钥匙串访问**，点一下应用窗口使其成为前台。
- 看 **屏幕顶部菜单栏**（紧贴屏幕左上角苹果 logo、显示「钥匙串访问」应用名的那一整条，不是钥匙串窗口里的工具栏）：**钥匙串访问 → 证书助理 → 从证书颁发机构请求证书…**。
- 对话框里：用户电子邮件、常用名称可填你的邮箱/名字；**CA 电子邮件留空**；选 **「存储到磁盘」**，保存得到 `**.certSigningRequest`**。

**C. 在网站上传 CSR、下载并安装证书**

- 回到网页 **Choose File**，选中该 CSR，Continue，生成证书后 **Download** 得到 `**.cer`**。
- 在访达中 **双击 `.cer`** 完成安装；默认进入 **登录** 钥匙串。

**D. 在钥匙串里确认并导出 P12**

- 钥匙串访问左侧选 **登录**，上方分类选 **我的证书**。
- 找到 **Developer ID Application: …**，展开确认下面有 **专用密钥**。
- 选中该证书行：**文件 → 导出项目…** → 格式 **个人信息交换 (.p12)** → 设导出密码并保存，例如 `~/DeveloperID.p12`。

**E. 生成 Base64 并更新 GitHub Environment Secret**

- 终端执行（路径换成你的文件）：

```bash
base64 -i ~/DeveloperID.p12 | pbcopy
```

- 将剪贴板内容完整粘贴到 `**BUILD_CERTIFICATE_BASE64**`；将导出 `.p12` 时设的密码写入 `**P12_PASSWORD**`；`**KEYCHAIN_PASSWORD**` 保持与工作流使用的一致（或新建强密码并同步改 workflow 若你自定义过）。

**F. 验证并重跑 CI**

- 本地可选：`security find-identity -v -p codesigning`，应含 **Developer ID Application:**。
- 推送 tag 或手动重跑 **Release** workflow。

---

## build.sh 增加错误日志透出 · 2026-05-03 19:59 · claude-opus-4-7

Release workflow (Xcode 16.4) 报 xcodebuild exit 65 + "(3 failures)"，但 GitHub Actions 日志里看不到具体的 `error:` 行——被 xcodebuild 的冗长输出淹没了。

改动：`build.sh` 把 xcodebuild 输出 tee 到 `build/xcodebuild.log`，失败时 grep `error:` 行打印出来再 exit。这样下次失败能直接看到编译错误。

背景：本地是 Xcode 26 (SDK 26.1)，CI 是 Xcode 16.4。项目部署目标 macOS 14.6 / Swift 5，理论兼容，但若代码用了新 SDK 才有的 API（如新版 SwiftUI / `@Observable` 新特性 / macOS 15+ 符号），16.4 会编译失败。需要等下次 tag push 拿到具体错误再修源码。

附带：日志里那条 `NSFileHandleOperationException: Broken pipe` 是 `xcodebuild -version | head -1` 的 SIGPIPE 噪音，跟构建失败无关。
# Intel（x86_64）支持 · 现状与恢复手册

> 状态：Intel 支持已于 **1.9.3** 移除，构建配置为 `ARCHS = arm64`。
> 本文记录**当时为什么移除**、**具体移除了什么**，以及**如果将来有足够用户呼声，怎么把 Intel 加回来**。
> 移除前的基线提交：`51b850a`（`git show 51b850a:"<路径>"` 可拿到带守卫的原文）。

## 什么时候才该做这件事

**触发条件只有一个：有用户明确要求 Intel 支持。** 没有人要求，就保持现状，不要主动加回去。

前面那次移除不是心血来潮 —— 那条路径当时是「名义支持、零验证、两处静默失效」。在没有 Intel 真机、没有 CI 覆盖的前提下把它加回来，只是把同一个问题重新种一遍。所以：

- 有人要求在 **2018–2020 款 Intel Mac**（macOS 14.6 以上）上跑 → 按本文恢复
- 没人要求 → 不动，本文继续放着

## 当时为什么移除（复述证据，避免以后重复调研）

1. **构建上一直是 universal，但从未在 Intel 上验证过。** README 的 Roadmap 自己把
   *"Additional validation across Intel, Apple Silicon, laptop, and desktop Macs"* 列成待办。
2. **CI 覆盖不了。** `.github/workflows/` 只跑 GitHub 的 macOS runner，现已全为 arm64，没有 Intel 矩阵。
3. **两处在 Intel 上静默失效**（详见下面「没做完的事」）：
   - DDC 私有 API 显示器亮度：整段 `#if arch(arm64)`，Intel 上编译成空实现，开关打开无反应也不报错
   - SMC 温度：只探 Apple Silicon 的键，仓库里没有 `TC0P` / `TC0D` / `TCXC` 那一族
4. **收益（实测，非估算）**：

   | | universal | arm64-only |
   |---|---:|---:|
   | 主二进制 | 12,577,984 B | 6,312,424 B（−49.8%） |
   | app 未压缩合计 | 14,118,308 B | 7,551,895 B（−46.5%） |

   参考：v1.9.2 的 DMG 是 4,882,286 B；1.9.3-beta.1（当时还是 universal）是 5,022,857 B。
   arm64-only 的 DMG 体积未实测，按切片比例粗估约 2.6 MB。

---

# 恢复清单

「恢复 Intel 支持」= 做完全部 4 项 + 处理最后一节的更新通道问题。只做第 1 项会编译不过。

## 1. 构建配置

`Light Stats.xcodeproj/project.pbxproj`：项目级 **Debug** 和 **Release** 两个 `XCBuildConfiguration`
各加了一行（位置在 `ALWAYS_SEARCH_USER_PATHS = NO;` 之后、`ASSETCATALOG_...` 之前）：

```
ARCHS = arm64;
```

删掉这两行即可回到 Xcode 默认的 `ARCHS_STANDARD`（arm64 + x86_64）。

注意：
- 全文件没有其它 `ARCHS` / `EXCLUDED_ARCHS` 设置，target 级配置不覆盖，靠项目级级联
- `ONLY_ACTIVE_ARCH = YES` 只写在 **Debug**，不影响发布包
- 解析结果自查：`xcodebuild -project "Light Stats.xcodeproj" -scheme "Light Stats" -configuration Release -showBuildSettings | grep ' ARCHS '`
  （App / FinderMenuExtension / LightStatsTests 都应显示 `ARCHS = arm64`，删掉后应变成 `arm64 x86_64`）

## 2. DDC 私有 API 的 arch 守卫（不恢复则 x86_64 编译不过）

**这不是可选优化，是让 x86_64 能编译的必要条件。**
`IOAVServiceCreateWithService` / `IOAVServiceReadI2C` / `IOAVServiceWriteI2C` 这些私有符号
只在 Apple Silicon 的 IOKit 上存在；`AppleCLCD2` / `IOMobileFramebufferShim` / `DCPAVServiceProxy`
这些 registry 类也一样。

### 2.1 `Light Stats/Services/DisplayControl/DDCTransport.swift`

移除前的守卫位置（行号是 `51b850a` 当时的）：

| 位置 | 结构 |
|---|---|
| L32–L62 | `#if arch(arm64)` 包住 `read(route:code:retries:)` 的函数体；`#else` 落 `return nil` |
| L72–L94 | `#if arch(arm64)` 包住 `write(route:code:value:retries:)` 的函数体；`#else` 落 `return false` |
| L98–L188 | `#if arch(arm64)` 包住整段私有实现：`writePacket` / `readReply` / `runKernelCall` / `kernelCallDidFinish` / `skipHungBus` / `KernelCallResult` |
| L191–L214 | `#if arch(arm64)` 包住文件级的 `DDCWatchdogBox` 类 |

两个 `#else` 分支**必须把参数全部消费掉**，否则 unused-parameter 警告：

```swift
// read(...) 的 #else
#else
        _ = route
        _ = code
        _ = retries
#endif
        return nil

// write(...) 的 #else
#else
        _ = route
        _ = code
        _ = value
        _ = retries
#endif
        return false
```

> 结构提示：这两处 `#if` 出现在**函数体内部**，不是包住整个函数 —— `#if` 在函数签名之后、
> 第一行语句之前，`#endif` 在 `return nil` / `return false` 之前。
> 如果写成包住整个函数，`#else` 里就没有可以消费参数的位置了。

### 2.2 `Light Stats/Services/DisplayControl/DisplayServiceMatcher.swift`

| 位置 | 结构 |
|---|---|
| L14–L61 | `#if arch(arm64)` 包住 `matchedServices(displayIDs:)` 的函数体；`#else` 是 `_ = displayIDs` + `return [:]` |
| L64–L253 | `#if arch(arm64)` 包住全部私有实现：`registryServices` / `framebufferServices` / `registryDisplay` / `dcpIndexForProxy` / `forEachService` / `displayDescriptor` / `edidFragments` / `usesMCDP29XXRoute` / `inheritedStringProperty` / `property`，以及 `RegistryService` / `MatchCandidate` 两个嵌套结构体 |

### 2.3 恢复方式

优先直接取原文，避免手写出错：

```bash
git show 51b850a:"Light Stats/Services/DisplayControl/DDCTransport.swift"
git show 51b850a:"Light Stats/Services/DisplayControl/DisplayServiceMatcher.swift"
```

但这两个文件在那之后**可能已有其它改动**（例如 DDC 重试逻辑调整），所以正确做法是：
以当前文件为基础，按上表结构把 `#if` / `#else` / `#endif` 手工加回，不要整文件覆盖。

改完自查：`grep -rn "#if arch(" --include=*.swift "Light Stats/" LightStatsTests/`
应能列出这 6 处（DDCTransport 4 处 + DisplayServiceMatcher 2 处）。

## 3. 注释（可选，无行为影响）

- `Light Stats/Services/SMCInfo.swift`：FPE2 的注释从 `Intel/M1 use FPE2 format:` 改成了纯格式描述
- `Light Stats/Services/PowerService.swift`：健康度回退链注释去掉了 `（Intel，mAh）`

**如果真的要支持 Intel 温度，这里不是加注释就能了事** —— 见下一节第 1 项。

## 4. 文档 / 元数据

- `AGENTS.md` **和** `CLAUDE.md`（两者是镜像，必须同步改）：
  `What this app is not` 一节里的 `- No Intel support — ...` 那条
- `README.md` / `README.zh.md` / `README.ja.md` / `README.ko.md`：
  各自的 **Requirements** 行 + **Roadmap** 行（四份都要改，别只改英文）
- `.github/ISSUE_TEMPLATE/bug_report.yml`：`Mac type` 下拉里被删掉的 `- Intel` 选项

---

# 没做完的事：只加回守卫 ≠ 支持 Intel

上面 4 项做完，x86_64 只是**能编译**。要算「支持」，下面这些缺口得先填，否则又是同一批静默失效：

1. **Intel 的 SMC 温度键。** 当前 `SMCInfo` 的 `cpuTempKeys` 只有
   `Te05` / `Tp01` / `Tp05` / `Tp09` / `Tp0D` / `Tp0Y` / `Tp0b` / `Tp0e` / `Tf04` / `Tf09` / `Tf0A` / `Tf0B` / `Tf0E`，
   全是 Apple Silicon 的。Intel 用的是 `TC0P` / `TC0D` / `TC0E` / `TC0F` / `TCXC` 那一族。
   不补的话，Intel 上健康分的 temperature 维度只剩 `ProcessInfo.thermalState`（维度不会消失，但没有真实 °C）。
2. **Intel 上的 DDC。** 不是补守卫就完事 —— Intel 的私有 API 完全是另一套（`IOFramebuffer` 的 I²C 接口），
   现有 `DDCTransport` 一行都用不了。真要支持等于**新写一个 transport**，并想清楚和现有
   `DDCServiceRoute` / `DisplayMatchScorer` 怎么共存。
3. **Intel 上的 GPU 利用率。** `GPUInfo` 走 `IOAccelerator` + `PerformanceStatistics`，候选键是
   `Device Utilization %` / `GPU Activity(%)` / `GPU Core Utilization`。Intel 集显/独显的键名不同，需真机验证。
4. **至少一台 Intel 真机 + 一次真机走查。** CI 覆盖不了（runner 全为 arm64），没有真机就只能靠猜。

# 恢复后的验证

```bash
# 1. 两个切片都在（App 和 Finder 扩展都要查）
lipo -info "build/DerivedData/Build/Products/Release/Light Stats.app/Contents/MacOS/Light Stats"
lipo -info "build/DerivedData/Build/Products/Release/Light Stats.app/Contents/PlugIns/FinderMenuExtension.appex/Contents/MacOS/FinderMenuExtension"

# 2. 不需要 Intel 机器：单独 cross-build x86_64 能过就说明守卫加对了
xcodebuild build -project "Light Stats.xcodeproj" -scheme "Light Stats" \
  -configuration Release -derivedDataPath /tmp/x86-check \
  -destination 'generic/platform=macOS' ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO

# 3. 常规门禁照跑
swiftlint lint --strict && ./script/validate_localization.sh
xcodebuild test -project "Light Stats.xcodeproj" -scheme "Light Stats" -destination 'platform=macOS'
```

---

# ⚠️ 更新通道：最容易被忘掉的一半

**改构建配置只解决「能不能装」。它不解决「怎么发出去」。** 这一节是当时调研的结论，加回 Intel 前必须重读。

## 已发布的 1.9.2 更新器拦不住任何东西

`UpdateService.verifySignature` 只有四道校验，**没有一道看架构**：

```
codesign --verify --deep --strict     ← 签名有效，与架构无关
spctl --assess --type execute         ← 问的是签名/公证，不比对当前机器架构
codesign -dv → TeamIdentifier         ← 团队 ID 相同
R2 渠道 SHA-256                        ← 哈希一致
```

一个 arm64-only 的包在 Intel 上这四道全过。

## 往渠道标记里加字段也没用

`latest-stable.json` / `latest-beta.json` 的实际形状：

```json
{"version":"1.9.2","file":"Light-Stats-1.9.2.dmg","notes":"..."}
```

`ReleaseInfo.Manifest` 只声明了 `version` / `file` / `notes`，Swift 合成的 `Decodable`
会**静默忽略**多余键。加 `"arch":"arm64"` 老客户端连读都不读。

## 而且更新没有回滚

`UpdateService.installAndRelaunch` 生成的脚本：

```sh
if /usr/bin/ditto "$SRC" "$DEST.new"; then
  /bin/rm -rf "$DEST"        # 旧包直接删，没有备份
  /bin/mv "$DEST.new" "$DEST"
  /usr/bin/open "$DEST"      # 架构不匹配时这里静默失败
fi
```

Intel 用户被更新后会变成：**App 消失、启动不起来、没有退路**，只能手动重装。

## 所以如果将来要「拦住 Intel 用户，让其维持现状」

只能靠**能启动的客户端**去拦，也就是必须**先发一个桥接版**：

1. **桥接版（universal + 闸门）**：保持 universal，在 `UpdateManager.check(userInitiated:)` 开头
   短路掉 Intel（`checkOnLaunch` 一并短路 → 不请求、零外发，符合项目「默认不外发」原则），
   About 页给一行说明 + 4 语言文案。这一版是 Intel 的终点站，功能照旧但不再收更新。
2. **再下一版起 arm64-only。**

残余漏洞（当时决定接受）：**一直停在桥接版之前、从没更新过的 Intel 用户**，
哪天手动点「检查更新」仍会拿到 arm64-only 并被弄坏 —— 因为那台机器上的客户端里没有闸门，改不了。
缓解手段只有「arm64-only 先只放 beta 渠道」或「stable 永远保持 universal（等于放弃瘦身）」。

> 当时的决定：**不做桥接版，直接 arm64-only**，理由是 Intel 用户基数很小
> （macOS 14.6+ 只覆盖 2017–2020 那几代 Intel 机型），且 `autoCheckUpdates` 默认关闭，
> 只有主动更新的人才会撞上。如果将来要恢复 Intel，这个决定需要重新评估。

# 决策记录

| 时间 | 决定 | 依据 |
|---|---|---|
| 1.9.3 | 移除 Intel 支持，`ARCHS = arm64` | 零验证路径 + 两处静默失效；无真机、无 CI；省掉约一半体积 |
| 1.9.3 | **不做** Intel 更新闸门 / 桥接版 | Intel 基数小、默认关自动更新；不想为小概率再加一个版本 |
| 1.9.3 | 保留本文 | 有用户呼声时可恢复；没人要求就不动 |

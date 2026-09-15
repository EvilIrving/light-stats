# 05 · 键、日志、资产、常量

---

## 一、UserDefaults 键（实测 47 个）

来自 `~/Library/Preferences/cools.wins.main.plist` [A]。

### 功能开关

```
edgeSnap                       Bool  true     屏幕边缘分屏
showSplitWindow                Bool  true     显示拖动预览框（FootprintWindow）
centerStatus                   Bool  true     窗口居中
nextDisplayStatus              Bool  true     下个显示器
prevDisplayStatus              Bool  true     上个显示器
hiddenAllWindowStatus          Bool  true     隐藏所有窗口
hiddenOtherWindowsStatus       Bool  true     隐藏其他窗口
enableShakeHiddenWindows       Bool  true     摇动窗口隐藏其他
enableDockPreview              Bool  true     Dock 窗口预览
enableFlickDock                Bool  false    Dock 窗口反转
commandTabPlus                 Bool  true     Cmd-Tab Plus
missionControlProStatus        Bool  true     调度中心 Pro
missionControlProClosesWindowStatus  Bool false
missionControlProQuitAppStatus       Bool false
moveDockToThisDisplayStatus    Bool  true     把 Dock 移到鼠标所在显示器
respectStageManager            Bool  true     预留台前调度空间
snapMarginEnable               Bool  false    分屏窗口间距（opt-in）
launchOnLogin                  Bool  true     开机启动
floatingColor                  Int   0        岛配色（灰/蓝/强调色）
```

### 数据

```
exclusionApps                  String JSON  "[]"          排除的 App
snappingIslandLayouts          String JSON  4 个内置布局   布局定义
snappingIslandSavedPlacements  String JSON  null          用户保存的位置
```

### 日志开关（每子系统独立，默认全关）

```
dockLockVerboseLog  dockPreviewVerboseLog  flickDockVerboseLog
hiddenAllWindowVerboseLog  hiddenOtherWindowsVerboseLog
missionControlProVerboseLog  commandTabPlusVerboseLog
windowDragPerfVerboseLog
```

### Dock 锁定（未启用，键已存在）

```
dockDisplayLock.enabled
dockDisplayLock.targetUUID
dockDisplayLock.targetUUIDs
dockDisplayLock.delayRecoveryPending
dockDisplayLock.delayRecoveryValue
dockDisplayLock.delayRecoveryHadValue
dockDisplayLock.orientationRecoveryPending
dockDisplayLock.orientationRecoveryValue
dockDisplayLock.noRestartMigrationCompleted
```

### 授权 / 更新 / 迁移

```
appVersion  purchaseActived  purchaseRemainDays
Paddle-Wins-781505-SD
updateEntitlementCheckedAt / ExpiresAt / LicenseCodeHash / PlanCode /
  TargetVersion / Type / VersionReleaseTime
SUEnableAutomaticChecks SULastCheckTime SULastProfileSubmissionDate
SUScheduledCheckInterval SUSendProfileInfo SUUpdateGroupIdentifier
```

---

## 二、`os.Logger` 子系统与分类

主程序日志子系统是 `cools.wins.main`。窗口管理相关的高频日志分类（从字符串表提取）[A]：

```
snapping.filter              拖动事件过滤
snapping.mouseDown / mouseUp
drag.*                       共 17 个：axWindowHitTest / axWindowRect / axWindowRectFallback /
                             windowServerRect / windowListRectFallback / axSizeSettable /
                             windowIdentifier / exclusionCheck / snapAreaDetection / stageManager /
                             cursorNudge / shake / edgeUpdate / islandUpdate / unsnapRestore /
                             flickDockPrepare / flickDockRelease
island.*                     show / hide / interactionUpdate / animationFrame /
                             layoutJSON / layoutReload / layoutSanitize
footprint.*                  targetRect / show / close
screen.detection / screen.inspected
window.enumeration / window.enumerationItems / window.screenshots / window.screenshot
```

专用的 dispatch queue 名（说明他们把活儿分了车道）[A]：

```
accessibilityCommandsQueue     AX 调用串行队列
global.userInteractive
wins.commandtabplus.appTitleCache
wins.commandtabplus.hoverDetection
wins.commandtabplus.runningAppIndex
wins.windowPreview.commonQueue
wins.windowPreview.hideDelayQueue     ← 预览隐藏用单独一条队列
wins.multiWindow.minimize.concurrent
```

`windowPreview.hideDelayQueue` 很说明问题：**预览的隐藏是延迟且可取消的**，所以他们给它单独的队列，避免被主队列的其它工作阻塞或取消。

---

## 三、稳定 reason code（诊断用）

Wins 大量使用 `key=value` 形式的稳定 reason code，而不是自然语言日志。可以直接照抄这套写法 [A]。

```
# 窗口解析
result=false reason=missing-target-ax-element
result=false reason=missing-target-wid
result=false reason=owner-pid-mismatch expectedPid=
result=false reason=target-ax-wid-mismatch axError=
result=false reason=scene-not-current kind=
result=false reason=target-not-proven targetFound=
result=false reason=thumbnail-wid-mismatch expectedWid=
result=false reason=windowserver-inventory-failed
result=false reason=invalid-expected-pid rawPid=
reason=notInCGS
reason=geometry-unavailable
reason=near-existing center={x=
reason=target-nil-or-closing targetWid=

# 关窗协调器
coordinator.request result=rejected reason=already-closing
coordinator.request result=rejected reason=incomplete-ticket
coordinator.request result=rejected reason=invalid-owner-pid
coordinator.finish result=ignored-stale request=
outcome: accepted | rejectedAlreadyClosing | rolledOver | closed |
         unconfirmed | aborted | sessionEnded

# Dock 预览 / 缩略图
decision=hover-xmark windowNumber=
decision=thumbnail-hit index=
decision=skip reason=closed-center-suppressed index=
decision=suppress-after-drag until=
decision=windowserver-fallback mode=
decision=windowserver-thumbnail-hit wid=
hover.no-thumbnail-hit ... detectorThumbnailCount= xVisible= hoverHash=
result=thumbnail-dead

# Dock 锁定
MoveError: prerequisitesNotMet | verificationFailed | displayDisconnected |
           accessibilityPermissionRequired | noReachableDockEdge |
           eventSourceUnavailable | dockProcessChanged
skipped=prerequisites unmet=
skipped=already-on-target target={id=
skipped=current-dock-unknown force=false target={id=
skipped=no-connected-target targets=
skipped=not-requested storedEnabled=

# 权限
reason=authorization
startup=true reason=screenRecordingPermission
eventtap.start result=authorization-rejected

# 私有 API 降级
sls-symbol-missing wid=
sls-owner-pid-failed wid=

# OS 版本差异
mode=macos27 result=ordered-front windowNumber=
mode=macos27 result=no-op-same-visible windowNumber=
mode=windowserver-fallback result=
mode=legacy windowNumber=
dock-observer result=skipped reason=macos-27 pid=
```

`hoverHash`、`geometryHitHashes`、`diagnosticLastSceneFingerprint` 这类**指纹**用来做"状态确实变了"的判定，避免重复日志——这个技巧我们的 `DiagnosticLogService` 值得采用。

---

## 四、AX 常量（他们实际用到的那一套）

**窗口角色白名单**（`AXSubrole`，三者之一才算"真窗口"）[A]：

```
AXStandardWindow    标准窗口
AXDocumentWindow    文档窗口
AXFloatingWindow    浮动窗口
```

**窗口过滤的三层启发式**（原文日志）[A]：

```
base rules rejected                          ← 基础规则就没过
skip untitled non-standard window (size=     ← 无标题 + 非标准角色 + 尺寸不符
skip dialog-like popup (untitled, size=      ← 无标题的对话框式弹窗
skip electron modal widget (title="          ← Electron 的 modal webview widget
modalwebviewwidget                           ← Electron 这个 class 的特征串
AXDialog                                     ← 对话框角色
```

**其它用到的 AX 常量**[A]：

```
子元素/角色    AXStaticText AXSeparator AXImage AXProgressIndicator AXCloseButton AXMinimizeButton
属性           AXVisibleChildren AXSelectedChildren AXFocusedUIElement
动作           AXRaise AXClose
通知           AXWindowCreated AXWindowMoved AXWindowResized AXWindowMiniaturized
               AXWindowDeminiaturized AXTitleChanged AXUIElementDestroyed
               AXMainWindowChanged AXFocusedWindowChanged
               AXApplicationActivated AXApplicationHidden AXApplicationShown
               AXApplicationDockItem AXIsApplicationRunning
调度/Mission   AXExposeShowAllWindows AXExposeShowFrontWindows AXExposeShowDesktop AXExposeExit
切换器         AXProcessSwitcherList
★ 关键开关     AXEnhancedUserInterface
```

**`AXEnhancedUserInterface` 是必须知道的一条。** 这是让 Electron / Java / 部分游戏应用把内部 AX 树暴露出来的开关——不设它，这些 App 的窗口在 AX 层几乎是空的。我们现在的 `TitlebarGestureService` 在 Electron 上不准，很可能就是缺这一步。

---

## 五、内置 App 黑名单（他们踩过的坑）

`__cstring` 里有一段连续的字符串数组 [A]。这是**Wins 自己在代码里排除的 App**，与用户可编辑的 `exclusionApps` 是两码事：

```
com.bilibili.bilibiliPC        com.openai.codex
com.youqu.todesk.mac           com.IdeaPunch.ColorSlurp
com.valvesoftware.steam        com.autodesk.AutoCAD
com.ssworks.drbetotte          com.goland.dvdfab.macos
org.videolan.vlc               org.mozilla.firefox
net.battle.bootstrapper        com.blizzard.worldofwarcraft
com.adobe.AfterEffects         com.adobe.Audition
org.oe-f.OpenBoard             com.apple.dt.Xcode
com.image-line.flstudio        com.colliderli.iina
com.apple.Preview              com.apple.iWork.Keynote
com.apple.iBooksX              com.apple.finder
com.electron.lark              com.alibaba.DingTalkMac
com.microsoft.teams2           com.microsoft.teams
com.apple.MobileSMS            com.apple.FaceTime
ru.keepcoder.Telegram          com.hammerandchisel.discord
com.tencent.WeWorkMac          io.github.clash-verge-rev.clash-verge-rev
com.west2online.ClashX         com.google.Chrome
com.google.android.studio
```

**外加一条正则**：

```
^com\.(jetbrains\.|google\.android\.studio).*?$
```

→ 覆盖全部 JetBrains IDE（IntelliJ/GoLand/PyCharm/Rider…）。

**外加一个进程名检查**：

```
wine64-preloader
```

→ Wine 应用。

**读法**：这些是"改了窗口会出事的 App"——视频/音乐播放器（会打断播放）、游戏（反作弊）、远程桌面、窗口管理工具自身、Adobe 全家桶、Electron 聊天软件（自绘窗口层）、Finder/Preview/Keynote 这类系统 App（有自己的一套规则）。**这是一份直接可用的踩坑清单**，我们要么照抄，要么在设置里默认带上并允许用户去掉。

---

## 六、SF Symbol 与资产

用到的 SF Symbol [A]：

```
square.split.2x1        arrow.counterclockwise     checkmark.circle.fill
xmark.circle.fill       exclamationmark.triangle.fill
```

`Assets.car` 的 27 个命名资产见 `01-package-inventory.md`。
特别记住 `FloatingGreyColor` / `FloatingBlueColor` / `FloatingActiveColor` 对应 `floatingColor` 三种岛配色。

---

## 七、URL 与外部跳转

```
https://wins.cool                              官网
https://api.wins.cool                          授权 API
https://wins.cool/update/appcast.xml           Sparkle feed
wins-internal://renew                          内部续费跳转
x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility
x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
x-apple.systempreferences:com.apple.preference.dock
x-apple.systempreferences:com.apple.Desktop-Settings.extension
```

另外他们用 AppleScript 打开系统设置面板：

```
do shell script "open -b com.apple.systempreferences ..."
```

（配合 entitlements 里只放行 `com.apple.systempreferences` 的 apple-events 例外。）

---

## 八、HTML/CSS（更新页）

`WinsUpdateExpiredDesignFile.html`（34 KB）与二进制里内嵌的 CSS 片段——更新页的发布说明是 **WKWebView 渲染 HTML**，样式是手写的 `#eaebee` 背景 + `-apple-system` 字体栈，含 `pre/code`、`img/video`、自定义滚动条。我们自己有更新窗口，可以直接用它的观感参考，不必通过 WebView。

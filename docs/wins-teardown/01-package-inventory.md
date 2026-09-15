# 01 · 安装包清单

`~/Downloads/Wins-latest.dmg` → 挂载后 → `/Applications/Wins.app`。
下面每一行都是实际检查过的。标注 **[A]** 为直接读出的事实。

## DMG（安装包本身）

| 项 | 值 | 说明 |
|----|----|----|
| 格式 | UDIF 只读 / zlib | `hdiutil imageinfo` |
| 大小 | 59,918,198 字节（57.2 MB），解压后 100,663,296 字节 | 压缩比 0.737 |
| 卷标 | `Wins` | 挂载为 `/Volumes/Wins` |
| 产品 | **DMG Canvas** | 背景文件名 `dmgcanvas_bg.tiff` 就是它的产物标记 |
| 背景图 | `.background/dmgcanvas_bg.tiff` → 219,910 字节，1296×758 | 粉白渐变 + 手绘卷曲箭头 + 两个模糊蓝圆 |
| 文案 | `Drag wins into Application folder to install` | 烧在背景图里，不是控件 |
| 图标布局 | `Wins.app` + `Applications → /Applications` 软链 | `.DS_Store` 存坐标 |
| 卷图标 | `.VolumeIcon.icns` 78,798 字节 | |
| 其它 | `.fseventsd/` | Finder 副产品 |

**可借鉴**：DMG 用 DMG Canvas 生成；背景图是唯一的视觉设计，没有安装器脚本、没有 pkg、没有许可协议弹窗。我们的 `script/build.sh` 可以对照检查是否也能到"拖一下就装完"。

## App 包结构

```
/Applications/Wins.app/Contents/
├── Info.plist                      2,289 B   LSUIElement=1，Sparkle 配置
├── MacOS/Wins                      6,241,888 B  x86_64 + arm64 双架构
├── Frameworks/
│   ├── Sparkle.framework           v2.7.1    自动更新
│   └── Paddle.framework            v1.0.0    授权/付费
├── Library/LoginItems/
│   └── WinsHelper.app              173,808 B  开机自启辅助进程（LSBackgroundOnly）
└── Resources/
    ├── Assets.car                  520,152 B  27 个命名资产
    ├── AppIcon.icns                 18,799 B
    ├── Base.lproj/Main.storyboardc/           13 个编译后的 nib
    ├── en/zh-Hans/zh-Hant/zh-HK/zh-TW/ja/de/es/fr/it.lproj/
    ├── Wins.prefPane/                         设置面板（挂进系统设置）
    ├── Wins_old.prefPane/                     旧版设置面板（保留兼容）
    ├── KeyboardShortcuts_KeyboardShortcuts.bundle/  KeyboardShortcuts 依赖的资源包（24 种语言）
    └── WinsUpdateExpiredDesignFile.html       34,367 B  更新页的 HTML/CSS 模板
```

## App 的 Info.plist 要点 [A]

| 键 | 值 | 意义 |
|----|----|----|
| `CFBundleIdentifier` | `cools.wins.main` | |
| `LSUIElement` | `1` | 无 Dock 图标、无菜单栏图标 |
| `NSMainStoryboardFile` | `Main` | 主故事板（只有一个 MainMenu + 若干窗口） |
| `LSMinimumSystemVersion` | `12.0` | 但代码里有 macOS 27 专用分支 |
| `NSAppleEventsUsageDescription` | 有 | 授权需要 |
| `NSAppTransportSecurity.NSAllowsArbitraryLoads` | `1` | 完全放开 ATS |
| `SUFeedURL` | `https://wins.cool/update/appcast.xml` | Sparkle appcast |
| `SUPublicEDKey` | `wqDJDN1i1qQpirkNpWfiCCCLbdDAxZNu8d5FLxQMTlo=` | Ed25519 更新签名公钥 |
| `SUEnableDownloaderService` / `SUEnableAutomaticChecks` | `1` | |
| `SUScheduledCheckInterval` | `43200`（12 小时） | |

## entitlements [A]

```
com.apple.security.app-sandbox                    false
com.apple.security.automation.apple-events        true
com.apple.security.cs.allow-jit                   true
com.apple.security.files.user-selected.read-only  true
com.apple.security.temporary-exception.apple-events = [com.apple.systempreferences]
```

**没有沙盒**，因此可以：直接读写别人的 AX 树、创建任意 level 的窗口、`SMAppService` 注册登录项。
`temporary-exception` 只放行 `com.apple.systempreferences` —— 用来从自己的界面跳转系统设置页（配合下面的 URL）。

## 链接的系统框架 [A]

常规：Foundation / AppKit / ApplicationServices / Carbon / ColorSync / Combine / CoreFoundation /
CoreGraphics / CoreServices / IOKit / QuartzCore / ServiceManagement / SwiftUI，以及一批 weak 链接的
`libswift*.dylib`（AVFoundation、Metal、QuickLookUI、Spatial、simd…）。

**唯一的私有框架：**

```
/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight   (version 600.0.0)
```

对照 `nm -u`，从 SkyLight 实际使用到的导出符号**只有 `SLSConnectionGetPID` 一个**，其余是 CoreGraphics 的公开 API
（`CGWindowListCopyWindowInfo`、`kCGWindowNumber/Bounds/OwnerPID/Layer/Alpha/IsOnscreen`、`CGDisplay*`、`CGWindowLevelForKey`）。

二进制里有 `sls-symbol-missing wid=`、`sls-owner-pid-failed wid=` 两条日志，说明是 **dlsym 动态解析 + 失败即降级**。

**结论：要复刻 Wins 的窗口管理，一个私有 API 都不需要。**（见 `06-substitutions-and-traps.md`）

## 三个内嵌 App / 插件

| 组件 | bundle id | 用途 |
|------|-----------|------|
| `Library/LoginItems/WinsHelper.app` | `cool.wins.WinsHelper` | `LSBackgroundOnly = true`，自带 Main storyboard 与 AppDelegate。典型的"登录项辅助进程"（`SMAppService`/`SMLoginItemSetEnabled` 需要一个独立 bundle 作为登录项）。功能上很小，只有 173 KB |
| `Wins.prefPane` | `cools.wins.preferences.panel` | v2.0.1，`NSPrincipalClass = WinsPreferencesPane`。真正的设置 UI |
| `Wins_old.prefPane` | — | 旧版设置面板，保留用于兼容老系统或老用户路径 |

## Wins.prefPane 内部 [A]

```
Contents/
├── Info.plist          2,090 B
├── MacOS/Wins          3,035,472 B   设置面板自己的可执行文件（独立于主程序！）
└── Resources/
    ├── WinsPreferencesPane.nib       编译后的 nib，自定义类只有两个：
    │                                   _TtC4Wins19WinsPreferencesPane（面板根）
    │                                   _TtC4Wins8MainView（内容视图）
    ├── WinsPreferencesPane.png       面板预览图
    ├── Assets.car
    ├── wins_25_1x.png
    ├── 22 × *.mp4                    内置功能演示视频（见下）
    ├── KeyboardShortcuts_KeyboardShortcuts.bundle
    └── {de,en,zh-Hans,zh-HK,zh-Hant}/*.lproj/Localizable.strings
```

要点：
- **设置面板是独立进程**（有自己的 3 MB 二进制），所以它自己也能申请权限、自己跑 SwiftUI。
- nib 里**几乎没有 UI 内容**——只有两个自定义类，全部界面是代码里搭的（SwiftUI 或程序化 AppKit）。这解释了为什么 `strings` 拿不到多少标签文字：文字都在代码字符串里，不在 nib 里。
- `Wins_old.prefPane` 说明他们经历过一次设置面板重写。

### 内置演示视频（22 段）

| 文件 | 时长 | 独有？ |
|------|-----:|--------|
| `snapIsland_en` / `snapIsland_zh` | 10.2s / 11.0s | 悬浮分屏岛 |
| `edgeSnap` | 3.6s | 屏幕边缘分屏（无语言变体） |
| `aeroShakeView_en` / `_zh` | 4.3s / 3.5s | 摇动窗口隐藏其他 |
| `shakeWindowToHiddenOtherWindows` | 2.6s | 同上（另一段） |
| `center_en` / `center_zh` | 19.1s / 13.3s | 窗口居中（最长的一段） |
| `nextDisplay` / `prevDisplay` | 6.3s / 6.3s | 跨屏 |
| `dockPreviewView_en` / `_zh` | 12.3s / 12.9s | **Dock 窗口预览（缩略图）** |
| `commandTabPlus` | 10.6s | Cmd-Tab Plus |
| `missionControlProStatus` | 7.1s | 调度中心 Pro |
| `missionControlProClosesWindow` | 6.6s | 调度中心里关窗 |
| `missionControlProQuitApp` | 7.4s | 调度中心里退 App |
| `dockLock` | 3.1s | Dock 锁定屏幕 |
| `flickDock` | 6.9s | Dock 窗口反转 |
| `hiddenAllWindow_en` / `_zh` | 3.1s | 隐藏所有窗口 |
| `hiddenOtherWindows_en` / `_zh` | 2.5s | 隐藏其他窗口 |

看画面的结论（已抽帧确认）：
- `dockPreviewView` = Dock 上方浮出一个面板，顶部写着 App 名，下面是该 App 的**真缩略图**，每张下面有窗口标题，鼠标悬停的那张背景变亮。与 Windows 任务栏预览一致。
- `missionControlProStatus` = 桌面上一个**蓝色描边的矩形**（2pt 左右），就是拖动过程中的 Footprint 预览框。
- `snapIsland` 系列演示的是分屏**结果**，岛的展开过程在设置面板左侧那张产品图里：屏幕顶部一条黑色横条，里面并排四个圆角方块（布局 tile）。

## Assets.car 里的 27 个命名资产 [A]

```
AppIcon                     logo                        logo2
ActivationIcon              PreviewCloseButton          previewCloseBtn
FloatingActiveColor   ★     FloatingBlueColor     ★     FloatingGreyColor   ★
ScreenRecordSVG             accessability               accessibilityIcon
authorizedStatus            unauthorizedStatus          nextStepButton
xMark                       xMarkForgredBackground
feature1  feature2  feature3  feature4  feature5  feature6
ZZZZPackedAsset-{1.0.0,2.0.0}-gamut{0,1}
```

★ 三个 `Floating*Color` 对应 plist 里的 `floatingColor`（实测值 `0`）——**岛上的 tile 有三种配色主题**（灰/蓝/主题色）。
`feature1..6` 是官网那六条卖点的图标。`ScreenRecordSVG` 印证了屏幕录制权限这条线。

## 版本与构建 [A]

| 项 | 值 |
|----|----|
| `CFBundleShortVersionString` / `CFBundleVersion` | 3.5.1 / 53 |
| SDK | `macosx27.0`（`DTSDKName`），`DTXcode 2700` |
| 构建机器 OS | `26A5421a` |
| prefPane 版本 | 2.0.1（用 SDK `macosx14.3.internal` 构建，明显更老，是另一个 target/时间线） |

**注意最后一行**：主程序用 macOS 27 SDK，设置面板却停留在 14.3 的 SDK。说明设置面板这条线长期没重建——这也解释了它为什么还在用 nib。

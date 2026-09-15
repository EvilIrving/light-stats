# Wins 参考素材

从 `/Applications/Wins.app` 3.5.1 抽出的**交互参考**素材。不做营销图、不做安装包大图、不留原视频。

来源标注：`main` = 主程序 `Assets.car`；`prefPane` = 设置面板 `Assets.car` / Resources。

## 目录

| 路径 | 内容 |
|------|------|
| `main/` | 权限/功能小图标、关闭钮、feature1–6 |
| `prefPane/` | 布局选择器 tile 底图、`plus` / `x.circle.fill` |
| `demos/frames/` | 每段功能演示的中间帧（优先中文） |
| `colors/named-colors.json` | 命名色（岛配色、面板控件色） |
| `strings/` | main + prefPane 的 Localizable.strings |
| `misc/` | 设置面板预览图、更新页 HTML |

刻意不收：墙纸、`WinsMainPhoto`、logo、icns、DMG 背景、原版 mp4、原始 `.car`。

## 演示帧对照

| 文件 | 功能 |
|------|------|
| `snapIsland_zh_f2.jpg` | 悬浮分屏岛 |
| `edgeSnap_f2.jpg` | 边缘分屏 |
| `dockPreviewView_zh_f2.jpg` | Dock 窗口预览 |
| `commandTabPlus_f2.jpg` | Cmd-Tab Plus |
| `missionControlProStatus_f2.jpg` | 调度中心 Pro / Footprint |
| `missionControlProClosesWindow_f2.jpg` | 调度中心里关窗 |
| `missionControlProQuitApp_f2.jpg` | 调度中心里退 App |
| `aeroShakeView_zh_f2.jpg` | Aero Shake |
| `shakeWindowToHiddenOtherWindows_f2.jpg` | 摇动隐藏其他 |
| `center_zh_f2.jpg` | 窗口居中 |
| `nextDisplay_f2.jpg` / `prevDisplay_f2.jpg` | 跨屏 |
| `hiddenAllWindow_zh_f2.jpg` / `hiddenOtherWindows_zh_f2.jpg` | 隐藏窗口 |
| `dockLock_f2.jpg` | Dock 锁定 |
| `flickDock_f2.jpg` | Dock 反转 |

## 岛配色（`floatingColor`）

见 `colors/named-colors.json`：

- `FloatingGreyColor` → sRGB ≈ `(0.525, 0.525, 0.525)`
- `FloatingBlueColor` → `systemBlueColor`
- `FloatingActiveColor` → 同 Grey（激活态）

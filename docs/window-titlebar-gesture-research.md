# 窗口标题栏手势：调研与优化方案

> 状态：调研完成；阶段一、阶段二已实施（见"实施结果"）。
>
> 结论先行：**标题栏手势不存在"通用精确解"**。标题栏在 Accessibility 层根本不存在（Electron 与原生 App 实测都是 nil），任何产品都只能做启发式判断。可行方向不是"更准地识别标题栏"，而是 ①用每个 App 自己暴露的红绿灯按钮现算标题栏高度、②拒绝在控件上起手、③给一个修饰键逃生通道。

## 一、问题背景

`TitlebarGestureService` 目前的手势模型：监听连续滚轮/触控板事件 → 累计位移越过阈值 → 取事件所在点找到"标题栏窗口" → 显示预览 → 越过提交阈值后执行吸附。

其中"找到标题栏窗口"分两条路：

1. 沿 AX 父链找 `AXTitleBar` 角色，或比对窗口的 `AXTitleUIElement`；
2. 找不到就退回几何判断：**窗口顶部 44pt 带内**就算标题栏。

实测表明第 1 条是死代码，第 2 条的 44pt 是错的。

## 二、实测数据（本机 macOS 26.4，单个 5K 显示器）

### 2.1 标题栏在 Accessibility 层不存在

| App | 类型 | `AXTitlebar` | `AXTitleUIElement` | 顶带命中测试返回 |
|---|---|---|---|---|
| cmux | 原生 | nil | nil | `AXGroup` / `AXTextArea` |
| VS Code | Electron | nil | nil | `AXGroup` / `AXScrollArea` |
| ChatGPT | Electron | nil | nil | `AXGroup` / `AXTextArea` |
| Fork | 原生 | nil | nil | `AXGroup` |
| 访达（最大化窗口） | 原生 | nil | nil | — |

**结论**：`titlebarWindowFromAccessibilityTree` 这条路径在当前生态下永远命中不了，实际生效的只有几何回退。Electron 的自定义标题栏是渲染进程里的网页内容，AX 树里表现为 `AXGroup` / `AXScrollArea` / `AXTextArea`，无法据此区分"拖拽区"与"内容区"。

Electron 官方文档印证了这一点：

- 自定义标题栏 = 网页里加 CSS `app-region: drag`，拖拽区只存在于渲染进程内部；
- `titleBarStyle: 'hidden' | 'hiddenInset' | 'customButtonsOnHover'`；
- `trafficLightPosition` 可以把红绿灯放到任意坐标；
- `setWindowButtonVisibility(false)` 可以让红绿灯整个消失。

即：**跨进程没有任何 API 能回答"这个点是不是拖拽区"**。

### 2.2 写死的 44pt 在两头都错

用红绿灯按钮簇反推每个 App 的真实标题栏高度：

```text
inset      = 红绿灯.minY − 窗口.minY
标题栏高度 ≈ 红绿灯.maxY + inset − 窗口.minY
```

| App | 红绿灯内缩 | 实测标题栏高度 | 与写死 44pt 的偏差 |
|---|---|---:|---|
| cmux | 8pt | 32pt | 偏大 12pt，捅进内容区 |
| VS Code | 9pt | 34pt | 偏大 10pt，捅进内容区 |
| ChatGPT | 15pt | 46pt | 基本刚好 |
| Fork | 18pt | 52pt | 偏小 8pt，够不到工具栏下半 |

反向的偏差同样有害：偏小会让手势在 Fork 这类统一工具栏窗口上"够不着"；偏大则会把内容区当成标题栏，在 VS Code、cmux 上误触发。

### 2.3 但红绿灯是可用的锚点

上面四个 App 全部把 `AXCloseButton` / `AXMinimizeButton` / `AXFullScreenButton` 作为窗口子元素暴露出来（原生与 Electron 都有），并且带坐标。命中测试红点得到的元素：

```text
cmux      → AXButton/AXCloseButton   （可直接识别）
VS Code   → AXButton/AXCloseButton   （可直接识别）
ChatGPT   → AXButton                 （无 subrole，但仍是按钮）
Fork      → AXGroup                  （只拿到按钮行容器）
```

所以："这个点是控件吗"可以用命中测试判断，但需要配合"是否落在红绿灯簇矩形内"一起用，单靠命中测试有反例（Fork）。

### 2.4 顶带里可能有交互控件

VS Code 的标签条、Chrome 的标签栏、Slack 的搜索框都长在窗口顶部。我们的滚轮 tap 是 `listenOnly`，不吞事件，于是会出现**一次滑动既切标签、又把窗口贴走**的叠加误判。这是当前实现最需要堵的洞。

## 三、市面上的做法

### 3.1 Swish（形态最接近）

- 区域模型：标题栏 / 程序坞 / 菜单栏 / 窗口边缘。
- 两指左右滑 = 左右半屏，上滑 = 全屏，下滑 = 最小化，捏合 = 关闭。
- "滑到方向后停住"出网格预览，选 1/4、1/3 位置。
- 要求辅助功能权限，macOS 12+，闭源。

官方文案明确是"在标题栏上滑"的模型（"Snap windows with a quick swipe on their titlebar"），但**没有公开如何识别标题栏**，也没有找到它在 Electron App 上可靠性的直接证据。

### 3.2 BetterTouchTool 社区"Swish 复刻"预设（最有价值的一条）

> Works on **window titlebars**, **dock icons**, or **anywhere on the screen if you hold the Fn key**.

这是业界对"标题栏识别不可靠"的正面回答：**加一个修饰键逃生通道**。按住修饰键时手势作用在指针下的窗口，不再依赖标题栏位置。该预设另外做了"连续滑动 → 在 1/3、2/3、居中之间循环"。

同一帖子里还有一条真实反馈值得注意：**滑动过快时预览窗会卡住不消失**（"the window preview pops up and gets stuck"）——这是带预览层实现的手势方案的通病。

### 3.3 Rectangle / Rectangle Pro / Magnet / BetterSnapTool

**完全不碰标题栏**：只做快捷键 + 把窗口拖到屏幕边缘/角落（snap areas）。Rectangle 官方标语是 "Memorize less: repeat shortcuts to cycle through window sizes" —— 用**循环**替代枚举，这是控制入口数量的另一种思路。

### 3.4 系统自带

macOS 15+ 自带：拖窗口到屏幕边缘平铺、绿灯菜单、`Fn+Ctrl+方向键`、以及"填充与排列"多窗口预设。本机相关开关：

```text
EnableTilingByEdgeDrag    = 0   （拖到屏幕边缘平铺：关闭）
EnableTopTilingByEdgeDrag = 0   （拖到菜单栏填充：关闭）
EnableTiledWindowMargins  = 0
```

也就是系统那条**最不容易误判**的路径（拖动窗口本身就是"移动窗口"的意图）当前是关闭状态。

### 3.5 生态结论

没有任何产品声称能可靠识别自定义标题栏。选择只有两种：**不碰标题栏**，或**加修饰键逃生通道**。

## 四、优化方案

### 阶段一（低风险，不改产品形态）

1. **标题栏高度现算**：用窗口的红绿灯按钮簇反推，取代写死的 44pt；无红绿灯（隐藏、无边框、全屏）时退回固定值。
2. **起手控件守卫**：手势开始时命中测试起点，落在按钮/输入框/标签条等交互元素上、或落在红绿灯簇内，就放弃这次手势（并记 reason）。
3. **预览生命周期硬保证**：手势结束（`ended`/`cancelled`）必定收起预览，堵掉 BTT 社区反馈的那类"预览卡住"。

### 阶段二（形态调整）

4. **修饰键逃生通道**：按住修饰键时，手势作用在**指针下的窗口**，不看标题栏、不做控件守卫。Electron、无边框、红绿灯被隐藏的窗口因此都能用，且不与 App 内手势争抢。
5. **暴露系统的边缘拖拽吸附**：让用户能直接看到并打开系统自带的拖到边缘平铺，把手势定位成增强入口而非唯一入口。

### 备选（本轮不做，记录备查）

6. **循环代替枚举**：左/右连按循环 1/2 → 2/3 → 1/3，可以省掉为 1/3 单独准备菜单项或手势（Rectangle 模式）。
7. **完全不判断标题栏**：把"指针下窗口 + 修饰键"直接作为唯一手势入口。

### 明确不做

- 继续调固定几何阈值（本轮就是把这个换掉）。
- 为识别标题栏注入其他进程：实测不稳定。

## 五、验收方式

- 诊断日志的 `windowManagement` 类别已有 `reason` 与布局证据字段；手势路径补充 `zone`（`titlebar` / `pointer`）与拒绝原因，用真实使用数据判断误判率，而不是靠手动试。
- 误判判据：在 VS Code 标签条 / Chrome 标签栏上滑动时，不应出现"标签切换 + 窗口吸附"叠加。
- 回归点：cmux(32pt) 与 VS Code(34pt) 上不应再有"内容区被当成标题栏"的触发；Fork(52pt) 上工具栏区域应能正常触发。

## 六、实施结果

阶段一、阶段二均已落地：

| 项 | 落点 |
|---|---|
| 标题栏高度现算 | `WindowSnapGeometry.titlebarHeight(windowFrame:trafficLights:)`，红绿灯簇由 `WindowGestureTargeting.trafficLights(of:)` 提供；无红绿灯时退回 44pt |
| 起手控件守卫 | `WindowGestureTargeting.isOnControl(...)`；`AXButton` / `AXTabGroup` / `AXSlider` 等视为控件，`AXScrollArea` / `AXTextArea` / `AXGroup` 故意不算（否则 Electron 全废） |
| 预览必定收起 | `TitlebarGestureService.endPreviewSession()`，手势 `ended` / `cancelled` 后无条件执行 |
| 修饰键逃生通道 | 按住 **Fn** → `SnapGestureZone.pointer`：只看指针下的窗口，跳过标题栏与控件判定 |
| 暴露系统边缘拖拽 | `SystemWindowTilingSetting` 读写 `com.apple.WindowManager`；设置项在窗口管理分区，首次开启窗口管理时自动打开一次 |

诊断：`windowManagement` 事件新增 `zone` 字段；新增 `gestureRejected` 动作，`reason` 为 `notTitlebar` / `control` / `noWindow` / `noElement` / `noWindowFrame`。

明确未采纳：继续调固定阈值；注入进程去识别标题栏。

备选未实施（见第四章）：循环代替枚举；把"指针下窗口 + 修饰键"直接作为唯一入口。

## 七、来源

- Electron 自定义标题栏文档：<https://www.electronjs.org/docs/latest/tutorial/custom-title-bar>
- Swish 官网：<https://highlyopinionated.co/swish/>
- macOS WM Directory（Swish 条目，区域模型与网格吸附说明）：<https://macoswm.com/wm/swish>
- BetterTouchTool 社区 "Swish-Style Window Management" 预设（修饰键逃生通道、连续滑动、预览卡住反馈）：<https://community.folivora.ai/t/swish-style-window-management-for-bettertouchtool/46437>
- Rectangle 官网（快捷键 + snap areas + 循环）：<https://rectangleapp.com/>
- 本机实测：AX 结构探测脚本输出（`AXTitlebar` / `AXTitleUIElement` / 红绿灯簇坐标 / 顶带命中测试），macOS 26.4；`defaults read com.apple.WindowManager`

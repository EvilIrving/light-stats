# 受众研究底稿（Audience Research）

> 目的：作为主题阵容、附加工具、软件引导决策的唯一事实来源。
> 任何「XX 人群占多少」的论断必须回本文档，禁止拍脑袋。
>
> 状态：**研究底稿**，持续更新。
> 数据采集方式：AnySearch 网络搜索（见文末来源 URL）。

## 一、硬数据（已核实）

| 事实 | 数值 | 来源 |
|---|---|---|
| 开发者里 macOS 占比 | ~33%（2025 SO 调查：32.9% 专业开发者主工作 OS；2024 为 31.8%） | Stack Overflow 2024/2025 调查 |
| 开发者性别 | ~92% 男性（SO 调查受访者） | Stack Overflow 调查 |
| 开发者暗色模式 | ~70% 每天在 IDE 用暗色 | gitnux.org 引 2023 SO 调查 |
| 桌面暗色模式 | Windows 11 69.4%、iOS 暗色 55–70% | gitnux / Earthweb |
| 明色少数派 | ~25–35% | wifitalents / forms.app 合成 |
| Mac 上的 PC 玩家 | Mac:Windows = 2.5:100（对比开发者 66.5:100） | Axis Intelligence |
| macOS 整体桌面份额 | ~15–20% 全球，~30% 美国 | StatCounter |
| 菜单栏 app 受众 | 「developers, creatives and power users」 | Timing app 博客 |
| 直接竞品 Stats | 41.2k GitHub stars、100M+ 下载、39 语言 | mac-stats.com / GitHub |

## 二、数据边界（诚实声明）

- **不存在**「macOS 系统监控 app 主题偏好」的现成公开数据。下文结论全部由代理数据反推。
- 「明色少数派 25–35%」是多个来源的**合成估计**，不是单一精确值。
- 「~92% 男」是 Stack Overflow **开发者受访者**的数字，不代表全体 Mac 用户；但本 app 受众是自我选择的科技爱好者（开发者占比高），故作为偏向上的参考。
- 桌面暗色模式各来源差异大（IDE ~70%、桌面 ~69%、web「prefer dark」22%），取区间而非单点。

## 三、数据推出的受众模型

### 按职业

- **开发者**：~1/3（~92% 男）
- **创作者 / 设计**：Mac 在设计与工程交叉人群占优
- **泛极客 / power user / Apple 原生党**：其余

来源对菜单栏监控类 app 受众的统称：「developers, creatives and power users」。

### 按明暗偏好（主题唯一该切的轴）

- 暗色：~65–70%
- 亮色：~25–35%

### 已被数据否决的假设

- **「RGB 装机党 / 电竞」段**：Mac 上 PC 玩家 Mac:Windows = 2.5:100，几乎为零。
  该段是 Windows 人群，**不得再作为 macOS 主题依据**。

## 四、对主题阵容的推论（暂存，待决策）

- 名额分配应贴合**暗/亮比**，而不是按「职业人格」分名额。
- **亮色主题需重新设计 ×2**（尚未想好，见未决线程）。
- 之前「赛博朋克 = RGB 装机党」的理由不成立，需换理由或放弃。

## 五、未决线程（待办）

1. **亮色主题重设计 ×2** —— 未定
2. **附加工具优化** —— 未定
3. **软件引导优化（onboarding）** —— 未定

## 六、来源 URL

- https://survey.stackoverflow.co/2024/technology
- https://survey.stackoverflow.co/2025/technology
- https://survey.stackoverflow.co/2024/
- https://gitnux.org/dark-mode-usage-statistics/
- https://earthweb.com/how-many-people-use-dark-mode/
- https://wifitalents.com/dark-mode-usage-statistics/
- https://forms.app/en/blog/dark-mode-statistics
- https://axis-intelligence.com/mac-vs-windows-market-share/
- https://commandlinux.com/statistics/macos-market-share-yearly-trends/
- https://timingapp.com/blog/best-mac-menu-bar-apps/
- https://github.com/exelban/stats
- https://mac-stats.com/
- https://medium.com/@davidroliver/why-developers-use-macs-and-why-the-data-says-something-different-0db661b1207a
- https://favtray.com/blog/best-mac-menu-bar-apps-developers
- https://dev.to/godnick/the-best-mac-menu-bar-apps-for-developers-in-2026-1h8j

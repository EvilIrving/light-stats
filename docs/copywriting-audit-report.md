# Light Stats 全面文案审查与四语言重构报告

> **编制说明**：本报告针对 Light Stats 全项目 **4 种支持语言（英语 en、简体中文 zh-Hans、日语 ja、韩语 ko）** 的用户可见文案（官网、App UI、README）以及非可见文案（研发、设计、产品、AI Agent 规范）进行全景式横向排查与深度审计。
> 
> **当前状态**：建议汇报与跨语言方案待审阶段，**尚未改动任何代码**。
> **本地与 CI 校验规则**：根据 `script/validate_localization.sh`，任何文案 key 的改动必须在 4 种语言中严格对齐。

---

## 目录
1. [四语言全局问题诊断](#一四语言全局问题诊断)
2. [第一部分：四语言 UI 文案横向对比与治理表](#二第一部分四语言-ui-文案横向对比与治理表)
3. [第二部分：官方网站多语言文案审计 (`website/index.html`)](#三第二部分官方网站多语言文案审计)
4. [第三部分：四语言 README 结构优化 (`README.{md,zh,ja,ko}`)](#四第三部分四语言-readme-结构优化)
5. [第四部分：非可见文案审计（研发/设计/产品/Agent）](#五第四部分非可见文案审计)
6. [第五部分：落地实施方案与优先级](#六第五部分落地实施方案与优先级)

---

## 一、四语言全局问题诊断

在比对了 `en`, `zh-Hans`, `ja`, `ko` 全部 550+ 个词条后，我们发现文案问题呈现两类典型形态：

### 1. 全语言共有硬伤（源头产品思维偏差）
- **开发者辩解与系统拉踩（四语言通病）**：如 `settings.snap.edgeOwner.hint`，在英、中、日、韩四国语言中，都原封不动保留了“同一个手势只有一个实现负责”、“macOS 自带只有对半与四角”这种开发者内部讨论和对 macOS 原生能力的拉踩抱怨。
- **过于随意的大白话口语（四语言通病）**：如 Dock 点击收起提示，英文是 `put its windows away; click again to bring them back`，日文是 `しまいます/戻します`（收玩具语气），韩文是 `접습니다/되돌립니다`，中文是 `收起来/放回来`。全语言均缺乏现代桌面系统的规范感。
- **AI 额度直译难懂（四语言通病）**：`tightest window` 在四国语言中各显神通，中文译为“最紧额度”，日文译为“最も逼迫した枠”，韩文译为“가장 부족한 할당”。普通用户看到完全无法理解背后的业务逻辑。

### 2. 语言本地化偏差（翻译事故或标准不一）
- **只有中文崩坏的词条**：
  - `settings.statusBar.separator`：英文 `Status Bar Divider`、日文 `ステータスバー区切り`、韩文 `상태 표시줄 구분선` 都是标准的“分隔线”，唯独中文被翻成了像交通/防疫设施的“**状态栏隔离栏**”。
  - `popover.action.about` & `quit`：英文、日文、韩文均严格遵循 macOS HIG 带上了应用名（`About Light Stats` / `Light Stats について` / `Light Stats 정보`），唯独中文写成了陈旧的“**关于软件**”和“**退出软件**”。
- **硬件误导（中日韩通病）**：
  - 英文名 `Find My Mouse` 属于双关戏谑（致敬苹果 Find My 和微软 PowerToys）。但直译成中文“**找到我的鼠标**”、日文“**マウスを探す**”、韩文“**마우스 찾기**”后，三国语言的亚洲用户第一反应全部是：寻找物理丢在桌底下的蓝牙鼠标（AirTag 逻辑），而没有表达出“屏幕光标高亮定位”的真实含义。
- **风格异化（仅中文页游化）**：
  - 光标样式在英文（`Holographic Silver`, `Ice Crystal`, `Rose Pink`, `Aurora`, `Obsidian`）、日文（片假名音译）、韩文（谚文音译）中都是雅致的矿石/光学意向；唯独中文翻译自行给每个样式加上了“钻”（全息银钻、玫瑰粉钻、曜石黑钻），瞬间滑向了页游道具风。

---

## 二、第一部分：四语言 UI 文案横向对比与治理表

> 注：下列所有词条修改方案均经跨语言语法与 macOS 本地化人机指南校准。

| Key / 编号 | 语言 | 当前文案 (Before) | 建议优化 (After) | 诊断分析与优化理由 |
| :--- | :--- | :--- | :--- | :--- |
| **KEY-01**<br>`aiUsage.collapseWindows` | **en**<br>**zh**<br>**ja**<br>**ko** | `Show the tightest window`<br>`收起为最紧额度`<br>`最も逼迫した枠だけ表示`<br>`가장 부족한 할당만 표시` | `Show primary quota only`<br>`仅显示主额度`<br>`主要な枠のみ表示`<br>`주요 할당만 표시` | **核心硬伤**：“tightest window / 最紧额度 / 逼迫した枠”为纯算法内部用语。从用户视角看，收起多周期时展示的是核心/最紧俏的主额度。优化后四语言表达通俗自然。 |
| **KEY-02**<br>`settings.statusBar.separator` | **en**<br>**zh**<br>**ja**<br>**ko** | `Status Bar Divider`<br>`状态栏隔离栏`<br>`ステータスバー区切り`<br>`상태 표시줄 구분선` | `Status Bar Divider` *(保持)*<br>`状态栏分隔线`<br>`ステータスバー区切り` *(保持)*<br>`상태 표시줄 구분선` *(保持)* | 中文的“隔离栏”严重偏离 UI 规范，修改为与英、日、韩完全对齐的“分隔线”。 |
| **KEY-03**<br>`update.available.message` | **en**<br>**zh**<br>**ja**<br>**ko** | `Signed, notarized update. Settings preserved.`<br>`已签公证，设置保留。`<br>`署名・公証済みの新バージョンです。設定はそのまま維持されます。`<br>`서명 및 공증된 업데이트입니다. 설정은 유지됩니다.` | `A new version is ready. Your settings will be preserved.`<br>`新版本已准备就绪，更新将保留你的所有设置。`<br>`新しいバージョンが利用可能です。設定はそのまま維持されます。`<br>`새로운 버전이 준비되었습니다. 설정은 그대로 유지됩니다.` | 剔除面向 Apple 审核的开发术语“公证（Notarized）”，转为亲切、规范的系统更新提示，保留“设置不丢失”的用户核心诉求。 |
| **KEY-04**<br>`settings.findMouse` | **en**<br>**zh**<br>**ja**<br>**ko** | `Find My Mouse`<br>`找到我的鼠标`<br>`マウスを探す`<br>`마우스 찾기` | `Locate Pointer`<br>`快速定位光标`<br>`ポインタを探す`<br>`포인터 찾기` | **消除硬件防丢误解**：将中日韩直接从“找实体鼠标（Mouse）”纠正为“定位屏幕指针/光标（Pointer）”，与 macOS 官方辅助功能术语严格统一。 |
| **KEY-05**<br>`settings.presentationCursor.style.*` | **zh** | `全息银钻 / 冰蓝水晶 / 玫瑰粉钻 / 极光彩钻 / 曜石黑钻` | `全息银 / 冰蓝 / 晨粉 / 极光 / 曜石黑` | 剔除中文译文自行添加的“钻”字后缀，与英文的矿物设计原名（Holographic Silver, Ice Crystal 等）以及日韩音译保持统一的现代简约质感。 |
| **KEY-06**<br>`settings.snap.edgeOwner.hint` | **en**<br><br>**zh**<br><br>**ja**<br><br>**ko** | `One gesture, one owner. Light Stats covers thirds, corners, and custom layouts; macOS covers halves and corners only, and shortcut placements use system commands too.`<br>`同一个手势只由一个实现负责。Light Stats 支持三分、四角和自定义布局；macOS 自带只有对半与四角，快捷键摆放也交给系统命令。`<br>`同じジェスチャはひとつの実装だけが担当します。Light Statsは1/3・四隅・カスタムレイアウトに対応し、macOS標準は半分と四隅のみ、ショートカット配置もシステムコマンドに任せます。`<br>`같은 동작의 구현은 항상 하나입니다. Light Stats는 3분할·사분면·사용자 레이아웃을 지원하고, macOS 기본은 반쪽과 사분면만 지원하며 명령이 있는 단축키 배치도 맡습니다.` | `Choose whether Light Stats or macOS handles edge snapping. Light Stats adds support for thirds, corners, and custom layouts.`<br><br>`选择由 Light Stats 还是系统处理边缘吸附。Light Stats 额外支持三分屏、四角吸附及丰富自定义布局。`<br><br>`端スナップの処理を Light Stats と macOS のどちらに任せるかを選択します。Light Stats は 1/3 分割や四隅、カスタム配置に対応しています。`<br><br>`화면 가장자리 스냅을 Light Stats와 macOS 중 어디서 처리할지 선택합니다. Light Stats는 3분할, 사분면 및 사용자 지정 레이아웃을 추가로 지원합니다.` | **重灾区彻底重塑**：全语言删除“内部手势只能由一个实现负责”等架构碎碎念，删除对“macOS 自带只有对半四角”的技术拉踩，转为客观阐明用户选择与 Light Stats 的增量优势。 |
| **KEY-07**<br>`settings.snap.dock.collapse.hint` | **en**<br>**zh**<br>**ja**<br>**ko** | `Click the frontmost app's Dock icon to put its windows away; click again to bring them back.`<br>`点最前面 App 的 Dock 图标，把它的窗口全部收起来；再点一次放回来。`<br>`最前面のAppのDockアイコンをクリックするとウインドウをすべてしまいます。もう一度クリックで戻します。`<br>`맨 앞 앱의 Dock 아이콘을 클릭하면 윈도우를 모두 접습니다. 다시 클릭하면 되돌립니다.` | `Click the active app's Dock icon to hide its windows, and click again to restore.`<br>`点击当前活跃 App 的 Dock 图标隐藏其所有窗口，再次点击即可恢复显示。`<br>`アクティブな App の Dock アイコンをクリックしてウインドウを隠し、もう一度クリックして復元します。`<br>`활성 앱의 Dock 아이콘을 클릭하여 모든 창을 숨기고, 다시 클릭하여 복원합니다.` | 四语言全部告别过分口语化的“收起来/放回来/しまいます/접습니다”，采用 macOS 标准的“隐藏/恢复”规范术语。 |
| **KEY-08**<br>`popover.action.about` & `quit` | **zh** | `关于软件`<br>`退出软件` | `关于 Light Stats`<br>`退出 Light Stats` | 补齐中文缺失的应用名称，与 `en` (`About Light Stats`), `ja` (`Light Stats について`), `ko` (`Light Stats 정보`) 完全对齐 HIG 规范。 |
| **KEY-09**<br>`settings.displayControl.hint` | **en**<br>**zh**<br>**ja**<br>**ko** | `KVM / hubs often block DDC, preventing hardware brightness.`<br>`KVM / 扩展坞常拦截 DDC，无法调硬件亮度。`<br>`KVM やハブは DDC を遮断することが多く、輝度を調整できない場合があります。`<br>`KVM이나 허브가 DDC를 차단하여 하드웨어 밝기 조절이 안 될 수 있습니다.` | `Adjusts external display hardware brightness via DDC (some hubs or adapters may not support DDC passthrough).`<br>`通过 DDC 协议调节外接显示器硬件亮度（部分转接器或扩展坞可能不支持）。`<br>`DDC プロトコル経由で外付けディスプレイの輝度を調整します（一部のハブやアダプタでは動作しない場合があります）。`<br>`DDC 프로토콜을 통해 외장 디스플레이의 밝기를 조절합니다(일부 허브나 어댑터는 지원하지 않을 수 있습니다).` | 四语言由“负向发泄抱怨语气”统一改为“客观功能说明 + 兼容性前提提示”。 |
| **KEY-10**<br>`settings.activation.invalid` | **en**<br>**zh** | `That code doesn't match — give it another look?`<br>`激活码没对上，再核对一下` | `Invalid activation code. Please check and try again.`<br>`激活码无效，请检查后重新输入` | 消除英中两版轻浮调侃的语气（日韩原本就很严谨礼貌：`コードが一致しません。もう一度ご確認ください` / `코드가 맞지 않아요. 다시 확인해 주세요`）。在授权关键报错时保持稳健。 |

---

## 三、第二部分：官方网站多语言文案审计

目前官方网站集中在 `website/index.html`。其文案主要是英文，但作为面向全球四国语言用户的门面，核心问题如下：

1. **移除内部策划泄漏的标签**：
   - 现存：`<span class="tag">Differentiator</span>`（第 489 行）
   - 优化：直接移除该标签，或改为面向用户的 `Network Insight`。
2. **改写居高临下的网络说明**：
   - 现存：`Throughput is the easy part. Light Stats also detects whether you are behind a proxy... and AS number.`
   - 优化：`Beyond upload and download speeds, Light Stats lets you see proxy status and your real public exit node at a glance.`（删掉“Throughput is the easy part”与生僻的“AS number”）。
3. **消除主题防卫性解释**：
   - 现存反复出现的：`Settings stays a plain white tool panel`（设置窗口保持白底工具面板）。
   - 优化：集中笔墨展现 4 款主题在菜单弹窗上的精致光影，删去对设置窗口未做换肤的解释。

---

## 四、第三部分：四语言 README 结构优化

当前仓库包含 4 份对应语言的主说明文档：
- 英语：`README.md`
- 中文：`README.zh.md`
- 日语：`README.ja.md`
- 韩语：`README.ko.md`

### 共同问题与四语言同步重构方案：

#### 1. 首段长难句拆分与核心提炼
- **现状（四语言相同）**：首段均是一整段长达 150 字的超长句，一口气塞入了 16 个功能，并且都在首段硬塞了“干净安装默认墨夜，设置窗口保持纯白系统面板”。
- **四语言重构标准**：
  - **en**：
    > **A native, lightweight macOS menu bar instrument designed for Apple Silicon.**
    > Move beyond misleading memory percentages. Light Stats folds real-time pressure signals into a single 0–100 health score, letting you know instantly if your Mac is actually struggling, while keeping AI quotas, network context, and workflow tools close at hand.
  - **zh-Hans**：
    > **专为 Apple Silicon 设计的 macOS 菜单栏轻量监控仪表。**
    > 告别只看内存占用的粗暴数字。Light Stats 将实时系统压力折算为 0–100 的综合健康分，让你一眼掌握 Mac 当下是否真正吃力；同时集成了 AI 订阅配额、网络代理与窗口管理等开发工作流工具。
  - **ja**：
    > **Apple Silicon のために設計された、軽量な macOS メニューバー型状態計器。**
    > メモリ使用率の数字だけに惑わされません。Light Stats はリアルタイムの負荷シグナルを 0〜100 の健康度スコアに統合し、Mac が本当に逼迫しているかをひと目で把握できます。さらに AI 使用量やネットワーク状態などの作業ツールも手元に揃えます。
  - **ko**：
    > **Apple Silicon을 위해 설계된 네이티브 macOS 메뉴 막대 상태 계기.**
    > 단순한 메모리 사용량 수치를 넘어, 실시간 시스템 압박을 0-100 건강도 점수로 종합하여 Mac이 실제로 버거워하는지 한눈에 파악할 수 있습니다. AI 구독 사용량, 네트워크 상태 및 창 관리 도구도 함께 제공합니다.

#### 2. 剔除功能清单中的实现黑话
- **四语言统一修正**：把 `AXIdentifier`、`event tap`、`红绿灯现算` 等底层开发词汇，替换为面向用户的“完美适配原生分屏”、“零后台消耗监听”等成熟产品表达。

---

## 五、第四部分：非可见文案审计

面向内部读者（研发、设计、PM、Agent）：

1. **`AGENTS.md` / `CLAUDE.md`（Agent 行为规则）**：
   - 1200+ 行超长巨石文档精简。将具体算法推导与历史踩坑剥离至 `docs/`，主干瘦身至 300 行核心分层架构，消除“粉色大象效应”（删除反向历史，只留正面现行规范）。
2. **`task.md`（研发待办）**：
   - 2026-08-23 的显示器亮度旧任务早已发布，将其归档至 `docs/archive/`，避免 Agent 与新研发误判任务状态。
3. **`DESIGN.md`（设计规范错位）**：
   - 现 `DESIGN.md` 仅包含官网 HTML/CSS 规范，将其重命名为 `website/DESIGN.md`，并在根目录真正建立《Light Stats 客户端主题与设计指南》。
4. **`GROWTH.md`（产品内部思考）**：
   - 建立内部商业术语与对外文案的防火墙，避免类似 `Differentiator`、`tightest quota` 再次外溢到生产环境。

---

## 六、第五部分：落地实施方案与优先级

根据 `./script/validate_localization.sh` 强校验的要求，我们推进时必须保证 **四语言原子级同步**：

```
[阶段 1: P0 级严重文案修复]
  ├── 1. 四语言 Localizable.strings 同步修改 (最紧额度/隔离栏/公证更新/光标定位)
  └── 2. 官网 website/index.html 移除 Differentiator 及生硬表述

[阶段 2: P1 级系统设置提示精修]
  ├── 1. 四语言同步更新窗口边缘吸附提示 (去除拉踩与辩解)
  ├── 2. 四语言同步更新 Dock 点击与显示器亮度提示 (去口语与抱怨)
  └── 3. 校验: 运行 ./script/validate_localization.sh 确保 0 报错

[阶段 3: P2 级门面与文档重塑]
  ├── 1. 同步重构 README.md, README.zh.md, README.ja.md, README.ko.md 首段
  └── 2. 剔除四大语言 README 中的 AXIdentifier 等代码黑话

[阶段 4: P3 级非可见研发资产归位]
  ├── 1. task.md 归档
  ├── 2. DESIGN.md 迁回 website 并补齐客户端设计指南
  └── 3. AGENTS.md / CLAUDE.md 提炼瘦身
```

---
*本报告已同步保存至本地 `docs/copywriting-audit-report.md` 与交互式 Artifact 中，供团队随时查阅与审定。*

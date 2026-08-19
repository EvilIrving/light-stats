# 监控指标研究：哪些数据值得加

> 产品研究笔记 · 2026-08-19（初稿 08-18；[macmenubar.app](https://macmenubar.app/) Next.js 全量分页爬取 317/317）  
> 目的：对照开源/头部菜单栏监视器与菜单栏市场目录，筛出**用户会关心、能改行为、且不白烧 CPU** 的增量信号。  
> 非实现计划；技术 API 细节见 `docs/stats-anylysis.md`。

---

## 1. 问题与约束

想「监控更多数据」，但不能：

- 堆用户不关心的数字填界面
- 为对标 Stats / iStat 的模块清单而扩表
- 默认采样拖垮常驻菜单栏进程

Light Stats 的产品边界（见 `PRODUCT.md`）：

- 读的是 **压力（responsiveness）**，不是容量仪表盘
- 差异化在 **health 合成 + 网络真相（proxy/exit）+ AI 用量上下文**
- 监控核心只读；一切贵的 / 有副作用的能力默认关

因此扩指标的标准不是「竞品有没有」，而是「加完之后用户会做什么，以及采样贵不贵」。

---

## 2. 筛选门槛（必须同时过）

| 门槛 | 含义 | 反例 |
|------|------|------|
| **会改行为** | 看到后能决定：杀进程、换网络、充电、备份换盘、停 AI | 电压轨、世界时钟 |
| **成本可控** | 默认轮询便宜；贵的采集低频或 opt-in | 1s 扫 SMART / 全量 SMC |
| **不稀释主角** | 不跟 health / 实时压力抢视觉；异常才出声优于常驻 vanity | 菜单栏塞满独立模块图标 |

分层采样建议（研究用原则，非定案）：

| 层 | 频率量级 | 适合放什么 |
|----|----------|------------|
| 热路径 | 与刷新率一致（约 1–5s） | CPU / GPU / mem pressure / 网速 / disk I/O / 温风扇 / health 输入 |
| 温路径 | 分钟级或事件驱动 | 蓝牙外设电量、接口/在线身份变化、会话流量累计、USB-C/PD 插拔 |
| 冷路径 | 小时 / 日 / 异常触发 | SMART 健康态、电池循环（已有则可更慢）、大体积历史 |

「能采到」≠「该展示」≠「该进默认采样」。

---

## 3. Light Stats 已有覆盖（对照用）

| 域 | 已有 | 备注 |
|----|------|------|
| CPU | 使用率、负载、per-core、进程侧 | 已进 health |
| GPU | 利用率 | 已进 health |
| Memory | pressure、swap、详细分解结构存在 | health 用 pressure+swap，**不是** used% |
| Disk | 容量相关展示 + **disk I/O** | 容量不进 health（有意为之） |
| Network | 吞吐 + proxy + exit node（opt-in） | 强于「只有上下行」的 Stats 默认叙事 |
| Battery | 电量、状态、剩余时间、循环、健康%、瓦数、温度 | Overview 已露出 cycles / W |
| Thermal | 温度、风扇、thermal state 进 health | |
| Process | Top-N / Cleanup | |
| AI | Claude / Codex / Gemini 用量窗口 | opt-in |
| 合成 | 0–100 health | 产品主读数 |

相对 Stats/iStat，**核心压力面并不缺货**；缺口主要在「外设电量 / 磁盘将死 / 网络身份补全 / 少数解释性伴生信号」，不在「再开十个传感器模块」。macmenubar 目录也支持同一判断：挤的是 AI 配额与异常护栏，不是 SMC 动物园。

---

## 4. 竞品对照（开源与头部）

### 4.1 Stats（exelban/stats）— 开源对标锚点

公开模块：CPU、GPU、RAM、Disk、Sensors、Network、Battery、**Bluetooth**、Clock。

营销侧还会提：频率、电压、功率、SMART、公网/本地 IP、多时区时钟。

社区真实「瞟一眼」高频：**CPU、内存、网速、谁在吃资源**；传感器功率偶用；电压/时钟很少当核心。

### 4.2 iStat Menus — 付费深度锚点

同核心集 + 规则告警 + 更长历史 + 天气 + 外设电量（偏 Apple 键鼠轨）+ 大量传感器。

可学的是 **阈值告警与「异常出现」**，不是把天气/历史大图搬进默认面板。

### 4.3 eul（gao-sun/eul）— 已半停滞

SwiftUI 菜单栏监视器；历史卖点含 **蓝牙设备电量**。说明该缺口长期被用户当差异化，不是 Stats 偶然加的。

### 4.4 菜单栏市场里的相邻「监视」品类

来自 [macmenubar.app](https://macmenubar.app/) **全量分页爬取**（见 §4.5）、姊妹站 [macmenubar.com/system-stats](https://macmenubar.com/system-stats/) 与同类产品观察：

| 方向 | 代表（目录内） | 对 Light Stats 的启示 |
|------|------|------------------------|
| 负载拟人化 | RunCat | 情绪化展示，不是新指标 |
| AI 费用/配额 | Burnrate、Tokenscope、AIQuota、CodexBar / Lite、AgentBar、OpenCode Stats、AI Plan Monitor、Claude Usage Systray、KimiCodeBar、Quotio、Minto… | 市场已从「有没有用量」卷到「窗口剩余 + 重置倒计时 + 撞墙预警」；增量在预警，不在 token 明细 / relay 合集 |
| 轻量状态条 | Lume、melllo、Netfluss（仅上下行）、NotchBar 系统 HUD | 默认卖点几乎总是 CPU / Mem /（温）/ Net；堆传感器不是刚需 |
| 连通性二值灯 | NetCheck（绿/灰一点）、Online Indicator（替换 Wi‑Fi 图标） | 「在不在线」本身就能改行为；极便宜 |
| 电池垂直 | Juicy（自定义阈值）、Battery Life and Health、Battery（充电限幅） | 告警阈值有人买单；**充电限幅是写副作用**，不是读监控 |
| 线缆 / PD 身份 | WhatCable、USB Connection Information | 插拔事件驱动；解释慢充 / USB2 — 会改换线行为 |
| 全家桶工具箱 | Vorssaint、Sensei、OneTouch | 监控常被塞进工具合集；继续单一 status item + health |
| Apple Silicon 深剖 | SiliconScope（目录外 / macmenubar.com） | ANE / Media Engine / 带宽属发烧友面；默认热路径不该跟 |
| 明文解释压力 | Pulsr、Actvt（目录外 / macmenubar.com） | 可学白话解释，不是再堆传感器行 |
| 输入/生产力统计 | Mac Input Stats（键鼠声纹 + AI 助手活跃） | 相邻品类；不是系统压力信号 |

补充：目录内有 **iStat Menus**，**未见 exelban/Stats 条目**——开源锚点仍有效，但「菜单栏应用商店货架」上的可见竞品更偏 iStat / 轻量条 / AI 配额，而不是 Stats 模块动物园。

### 4.5 macmenubar.app 全量爬取（2026-08-19）

站点是 **Next.js App Router**（`_next/static`，不是 Nuxt）。列表数据嵌在 SSR 的 `self.__next_f.push` RSC 载荷里的 `apps[]`；分类路径 + `?page=N`（每页 24 条）可翻页。本次按全部分类路径分页抓取，与 `sitemap.xml` 的 `/app/*` **对齐 317 / 317**。

| 标签（可多选） | 条目数 | 备注 |
|----------------|-------:|------|
| productivity | 149 | 最大桶，含大量非监视工具 |
| system-tools | 89 | 监视、清理、keep-awake、端口等混装 |
| ai / development | 各 47 | AI 用量工具主要落这里 |
| hardware-devices | 18 | 电池、线缆、风扇、外设控制 |
| health | 14 | 多为久坐/护眼，不是 SMC health |
| dynamic-island | 9 | 部分带系统 HUD |

对扩指标有用的市场事实（有爬取字段支撑）：

1. **最小可行监视器反复验证同一短清单。** melllo = CPU + Temperature + RAM；Lume = System Activity Monitor；Netfluss = 仅实时上下行。没有人靠「电压轨」冷启动获客。
2. **异常/身份类产品单独成活。** NetCheck / Online Indicator 卖在线态；WhatCable / USB Connection Information 卖线缆与 PD；Juicy 卖自定义低电/健康告警。说明「异常才出声」和「插拔才出现」在商业上成立。
3. **AI 配额是独立品类。** 目录内至少十余个直接卖 usage / quota / reset / cost 的菜单栏应用（上表）；Light Stats 已有 Claude / Codex / Gemini 窗口，对齐「撞墙与重置」即可，不必追 Quotio / AI Plan Monitor 式多账号·relay 合集。
4. **控制类硬件工具很多，越出只读监控。** Battery 充电限幅、Macs Fan Control、MonitorControl / DisplayBuddy、PairPods——会改行为，但是写副作用。
5. **蓝牙电量仍散落。** PairPods 等仍把「可读则显示电量」当卖点；外设低电缺口没有消失。
6. **开发机端口监视成邻近赛道。** TidyPorts / Blink / Port Menu / PortKiller——真会改行为，但是另一品类，不进压力仪器。

一句话：全量爬取强化的不是「再加传感器模块」，而是 **轻默认读数 + 事件/异常护栏 + AI 撞墙**；并确认 **USB-C / PD 身份** 与 **在线二值** 值得留在短名单。

---

## 5. 短名单：值得认真研究

按「用户关心 × 成本」排序。均为候选，不是承诺。

### 5.1 蓝牙外设电量 — 优先评估

| | |
|--|--|
| **为什么** | Stats / eul / iStat 都长期投入；macmenubar 上 PairPods 等仍把可读电量当卖点；开会键鼠/耳机没电是真实中断 |
| **行动** | 去充电 / 换设备 |
| **工程成本** | **中低**。Stats 将该模块标为技术难度「低」：`IOBluetooth` → `pairedDevices()` → 读连接态/电量。MVP 是薄 Service + Model + 折叠展示；贵的是产品边角（见下），不是 API 硬骨头 |
| **运行成本** | 温路径下对 **内存 / CPU 增量通常可忽略**（几个设备结构体；连接变化 + 分钟级兜底）。勿跟 1–5s 热路径同频。Stats「Sensors + Bluetooth 禁用省 ~50% CPU」是两者合计，且 Sensors（全量 SMC）才是大头，不能当成蓝牙单独吃一半。更真实的风险是**高频戳蓝牙栈唤醒射频**，拖累本机与外设耗电 |
| **采样** | 连接/断开事件驱动 + 分钟级兜底；不进 health；不进默认菜单栏主读数 |
| **展示** | 挂电池条带旁或折叠；低电可比常驻 % 更醒目 |
| **与哲学** | 温路径 + 异常/低电更醒目，符合「不堆常驻 vanity」 |

**产品边界结论（研究拍板，供立项沿用）：**

| 问题 | 结论 | 理由 |
|------|------|------|
| 杂牌经常没有电量 | **能读就显示，读不到隐藏**；不做 Apple 白名单 | 白名单维护贵且漏真设备；缺失是常态，UI 沉默即可，不要显示 `0%` /「未知」占位刷存在感 |
| AirPods 左右耳 / 盒要不要拆 | **MVP 不拆**：按系统给出的设备级读数展示一套（或系统已聚合的一值） | 拆分是打磨项，不挡住「开会前看一眼会不会没电」；左右耳电量差很少改变「去充电」这一行动 |
| 断开的已配对设备要不要显示 | **默认只显示当前已连接** | 断开设备电量常过时或不可读；列表一对就变长，稀释「此刻能不能用」；已配对未连接不是压力/中断信号 |
| 要不要低电 toast | **默认不做 toast / 菜单栏角标**；低电只在 popover（或电池折叠区）更醒目 | 监控核心保持安静；系统已有部分外设低电通知。若以后加，必须 opt-in，且仅「已连接 + 可读 + 低于阈值」边沿触发一次，禁止轮询刷屏 |

仍待实现时确认的细节（不挡结论）：阈值百分比用多少、折叠区文案、是否允许设置里打开 opt-in 低电提醒。

### 5.2 整机 / 封装功耗（W）作热力伴生

| | |
|--|--|
| **为什么** | 解释「为什么烫 / 风扇转 / 插电也耗电」；笔记本侧已有 `powerWatts` |
| **行动** | 关耗电进程、理解散热，而非再看一个 CPU% |
| **成本** | 走现有 SMC/热路径，勿另起高频通道 |
| **展示** | 并进 thermal 条；台式机 / 插电场景价值更高 |
| **注意** | 传感器缺失时沉默；不要做成 Stats 式电压电流表 |

### 5.3 磁盘 SMART「健康态」— 冷路径护栏

| | |
|--|--|
| **为什么** | 用户不关心 SMART 属性表；关心 Failing vs OK |
| **行动** | 备份 / 换盘 |
| **成本** | 小时或日级；禁止 1–2s 轮询 |
| **展示** | **异常才出现**；健康时完全沉默 |
| **与哲学** | 容量 % 不进 health 的决定保持不变；这是故障护栏，不是压力信号 |

### 5.4 网络「身份」强化（吞吐之外）

| | |
|--|--|
| **已有优势** | proxy + exit node 已强于多数「只有上下行」工具 |
| **可增量** | 主接口类型：Wi‑Fi / 有线 / VPN(`utun`)；可选：会话或当日流量累计；**在线/离线二值**（NetCheck / Online Indicator）；吞吐本身已有 Netfluss 证明「只卖上下行」也能独立成活——你们已有吞吐，缺的是身份而非再一个速率条 |
| **成本** | 接口 / 可达性变化事件驱动；累计用低频；在线态几乎免费 |
| **不要** | 为对标而加公网 IP 常驻、多时区时钟、远程 Web dashboard、内建测速常驻（Bolt 式测速可留给手动动作） |

### 5.5 AI：从「用量展示」到「会不会撞墙」

| | |
|--|--|
| **市场信号** | 全量目录里 AI usage/quota 工具成串（Burnrate、Tokenscope、AIQuota、CodexBar/Lite、AgentBar、OpenCode Stats、Claude Usage Systray、KimiCodeBar、Quotio、Minto、AI Plan Monitor…）；用户焦虑是「窗口打满 / 何时重置」不是「再看一个 token 细项」 |
| **你们已有** | Claude / Codex / Gemini 窗口 |
| **增量方向** | 接近限额的 warning 态、**窗口重置倒计时**、简短 toast — 对齐 AIQuota 的 gauges / reset timers / warning states，不是再铺 per-model 明细或第三方 relay 余额 |
| **成本** | 保持 opt-in；不进默认网络请求；不跟 AI Plan Monitor 抢「全网关账号合集」 |

### 5.6 USB-C / 充电 PD「身份」— 事件驱动候选

| | |
|--|--|
| **为什么** | WhatCable / USB Connection Information 单独成活：同一口型下线缆能力差一个数量级；「充得慢 / 只有 USB2」是真实中断 |
| **行动** | 换线、换充电器、换口、停止指望该线跑盘 |
| **成本** | **插拔 / 电源变化时读**，禁止跟刷新率同频扫 IOKit |
| **展示** | 异常或刚插入时解释一句（如「线缆仅 60W / 协商到 USB2」）；健康常驻不占菜单栏主读数 |
| **与哲学** | 温/冷路径 + 会改行为；不是再开一个 Sensors 模块。与已有 `powerWatts` 可互补（瓦数 vs 线缆/PD 上限） |
| **风险** | 台式 / 无电池机价值低；杂牌描述可能不准 — UI 必须容忍「未知」 |

相对 5.1–5.3，优先级更低：场景更窄（主要笔记本 + 外接充电/盘），但门槛能过，值得记在短名单而不是拒绝表。

---

## 6. 明确不该加（竞品有也拒绝）

| 指标 / 能力 | 拒绝理由 |
|-------------|---------|
| 电压 / 电流轨 | 几乎无人据此行动；传感器噪音大 |
| CPU/GPU 频率曲线作默认 UI | 发烧友玩具；Apple Silicon 解读成本高 |
| ANE / Media Engine / 内存带宽常驻（SiliconScope 式） | 对少数 AI/媒体负载有解释力；默认采样贵、受众窄，不符合压力仪器 |
| 风扇控制（Macs Fan Control 等） | Stats 已标 not maintained；风险 > 价值；且属写控制 |
| 电池充电限幅（Battery / AlDente 式） | 会改行为，但是**写副作用**；越出「监控只读」 |
| active/inactive/wired/speculative 推主界面 | 结构可留作内部；健康叙事应继续用 pressure+swap |
| 天气、世界时钟 | 不是系统压力产品 |
| 多日历史大图、远程监控面板 | 重存储/网络；与轻量菜单栏仪器冲突 |
| 磁盘占用 % 进 health | 容量警报 ≠ 卡顿；已否决 |
| Stats 式多独立菜单栏图标默认全开 | 占栏、稀释主读数；与单一 status item + health 路径相反 |
| 默认高频扫全量 SMC | 为「看起来专业」付 CPU 税 |
| 常驻测速 / ping 曲线 | Bolt / NotchBar ping 证明有人要，但是主动网络动作；最多手动，不进默认热路径 |
| 开发机端口 / 模拟器清单（TidyPorts 等） | 真会改行为，但是另一品类；不进系统压力仪器 |
| 盖子开合角度、电池人格旁白 | 目录里有（LidAngleSensor、Battery Beggar）；过不了「会改行为」或会稀释仪器语气 |
| AI relay 余额 / 多账号合集仪表盘 | AI Plan Monitor 的赛道；你们差异化是本机 CLI 窗口，不是第三方站余额 |

---

## 7. 与现有设计原则的对齐方式

扩监控时优先顺序建议：

1. **把已有信号说得更准**（pressure、swap/page rate、thermal、disk I/O、瓦数是否足够显眼）  
2. **加「异常才出现」的护栏**（SMART、外设低电、AI 撞限额）  
3. **最后才考虑常驻新读数**；且必须过第 2 节三门槛  

一句话：

> 对照开源产品，是为了找「用户会因此做什么」的缺口，不是找功能清单对标。

当前最站得住脚的增量方向（研究结论，待你拍板）：

1. 蓝牙外设电量（慢采；产品边界见 §5.1 已拍板）  
2. 功耗 / 热伴生说清（尤其插电 / 台式）  
3. 磁盘健康异常提示（冷路径、沉默默认）  
4. （次优先）网络身份补全：接口类型 + 在线二值；以及 AI 窗口的 warning / 重置倒计时  
5. （更次）USB-C / PD 身份 — 仅事件驱动，不进默认热路径  

其余 Stats / SiliconScope 式传感器扩张，以及目录里的充电限幅 / 风扇控制 / 测速常驻，不符合「不要堆没人关心的数」或越出只读监控。

macmenubar.app 扫描的额外确认：市场愿意为**极简读数**和**异常护栏**付钱，不愿意默认养活完整传感器动物园。

---

## 8. 晚上可带着看的问题清单

- [x] 蓝牙电量：~~只做 Apple / 能读就显示？~~ → **能读显示、读不到隐藏**（见 §5.1）  
- [x] 外设低电 toast / 角标？ → **默认否，只在 popover 更醒目**；若加须 opt-in（见 §5.1）  
- [x] AirPods 左右耳/盒拆分？断开已配对是否列出？ → **MVP 不拆；默认仅已连接**（见 §5.1）  
- [ ] package power：现有 `BatteryInfo.powerWatts` 在插电/台式是否已经够，还是缺独立系统功率？  
- [ ] SMART：只做内置盘还是所有已挂载卷？失败态文案怎么写才不像恐吓？  
- [ ] 网络身份：Wi‑Fi/有线/VPN 是否已能从现有 Network/Proxy 模型推导？在线二值是否值得在 status item 用极轻信号表达？  
- [ ] AI 撞墙：阈值用「窗口剩余 %」、还是「预计耗尽时间」、还是「重置倒计时」（AIQuota 路线）？  
- [ ] USB-C / PD：只在慢充 / 协商异常时出一句，还是插线就短暂露出？台式是否直接不做？  
- [ ] 有没有任何指标你主观很想加，但过不了「会改行为」？记下并主动丢弃（盖子角度、人格旁白、ANE 仪表等已预丢）。

---

## 9. 参考

| 来源 | 用途 |
|------|------|
| [exelban/stats](https://github.com/exelban/stats) / [mac-stats.com](https://mac-stats.com/) | 开源模块全集 |
| [iStat Menus](https://bjango.com/mac/istatmenus/) | 付费深度与告警/外设 |
| [gao-sun/eul](https://github.com/gao-sun/eul) | 蓝牙电量作为历史卖点 |
| [macmenubar.app](https://macmenubar.app/) | Next.js 目录全量分页爬取（317/317，RSC `apps[]` + `?page=`）；品类密度与相邻工具 |
| [macmenubar.com/system-stats](https://macmenubar.com/system-stats/) | 系统监视品类专辑（Pulsr、Actvt、SiliconScope 等；部分不在 .app 目录） |
| WhatCable / USB Connection Information / NetCheck / Online Indicator / Netfluss / Juicy / AIQuota 等 | 异常护栏、吞吐极简条、身份类产品如何单独成活 |
| `PRODUCT.md` | 产品定位与反模式 |
| `docs/stats-anylysis.md` | Stats 技术实现（API 层） |
| HN 讨论（Stats 相关帖） | 用户实际盯的是 CPU/Mem/Net，不是全传感器 |

---

## 10. 状态

- 性质：产品研究笔记，可单独阅读  
- 不绑定版本号；结论变更时改本节日期与短名单即可  
- 2026-08-19：直接爬取 macmenubar.app（Next.js RSC + 分页，317/317）→ 强化 AI 撞墙/重置、网络在线二值与 Netfluss 极简吞吐；新增 USB-C/PD 事件驱动候选；扩充拒绝表；注明目录未见 Stats 条目  
- 2026-08-19：§5.1 蓝牙电量补工程/运行成本结论，并拍板产品边界——能读显示/读不到隐藏、MVP 不拆 AirPods 左右耳盒、默认仅已连接、默认无 toast/角标  
- 若某条短名单立项，另开实现笔记或 PR，不在本文堆代码方案
`)
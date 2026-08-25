# Project Memory

## 安装包稳定下载走 Cloudflare R2 · 2026-08-25 11:35 CST · grok

站点给人点的安装包不再用会随 tag 变的 GitHub Releases 附件地址。R2 桶 `light-stats` 绑在 `download.onecat.dev`。稳定 permalink **不能以 `.dmg` 结尾**：浏览器（尤其 Safari）会用 URL 最后一段当文件名，点 `Light-Stats.dmg` 就会存成不带版本的包。对外地址是 `https://download.onecat.dev/stable` 与 `https://download.onecat.dev/beta`。Worker `light-stats-download` 把它们 302 到 `Light-Stats-<version>.dmg`。旧的 `/Light-Stats.dmg` 与 `/Light-Stats-beta.dmg` 仍跳转，只作兼容。Worker 读 `latest-stable.json` / `latest-beta.json`。校验和是 `SHA256SUMS.txt` 与 `SHA256SUMS-beta.txt`。应用内自动更新仍只打 GitHub Releases。

发版时 `release.yml` 的 publish job 在创建 GitHub Release 之后调用 `script/upload-r2.sh`。仓库 Secrets 是 `R2_ACCOUNT_ID` / `R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`（S3 兼容 API，账号级，可写该桶）；Variable `R2_BUCKET` 默认 `light-stats`。不要把 R2 密钥写进仓库。边缘对 latest 可能仍套 zone 默认约 4 小时 TTL；覆盖后新 ETag 会在重新校验时生效。GitHub Pages 的 Download 按钮和 JSON-LD `downloadUrl` 指向正式包；Beta 是旁边的次要入口。

## CALayer 复制初始化禁止重建子图层 · 2026-08-19 16:28 CST · agent

状态栏风扇迁移到独立 Core Animation 图层后，曾在 `FanAnimationLayer.init(layer:)` 中调用普通初始化共用的 `configure()`。这会在 Core Animation 创建 presentation layer 时再次执行 `addSublayer(iconLayer)`，把 model layer 加入复制层，稳定触发 `CALayerInvalidTree: expecting model layer not copy` 并终止进程。只构造对象或检查 model layer 的测试发现不了这个问题；必须把图层放进真实的 layer-backed window、提交动画并访问 `presentation()` 才能覆盖该路径。

以后所有带自定义子图层的 `CALayer` 子类都应区分两条初始化路径：`init()` / `init(coder:)` 可以搭建模型层树；`init(layer:)` 只能接受 `super.init(layer:)` 已复制的树、复制必要的自定义状态，并把属性重新绑定到已复制的子图层，禁止调用会新增子图层的公共 `configure()`。`FanAnimationLayer` 当前复制 `phase`、`currentSpeed`、mask scale，并复用复制后的 icon layer 与 mask；RPM 映射、动画时间模型、布局和着色架构保持不变。

回归网位于 `LightStatsTests/FanAnimationLayerTests.swift` 的 presentation-layer 测试：使用 layer-backed `NSWindow` 启动 2500 RPM 动画，访问 `presentation()`，并确认 model/presentation 各只有一个子图层。修复后相关测试 4/4、完整 XCTest 117/117、SwiftLint strict 均通过，Debug 应用启动并持续存活。

## 自动更新校验必须避免 Pipe 死锁 · 2026-08-19 13:59 CST · agent

Beta2 点击检查并安装 Beta3 时，更新窗口曾永久停在“正在校验并安装”。已确认 v1.9.1-beta.3 的 DMG 本身没有安全问题：`codesign --verify --deep --strict` 通过，`spctl --assess --type execute` 返回 `accepted / source=Notarized Developer ID`，Team ID 为预期的 `QZZ878S3NS`。

根因是 `Light Stats/Services/UpdateService.swift` 旧实现对 `Process` 使用 stdout/stderr `Pipe`，先读 stdout 再读 stderr。`hdiutil attach` 等系统命令输出较多时，某个管道可能写满，子进程阻塞等待，父进程也永久等待，因此 UI 无法从 installing 状态退出。以后不要把这类校验命令改回同步 `readDataToEndOfFile()` + `waitUntilExit()` 的 Pipe 模式。

当前实现改为异步轮询子进程，stdout/stderr 写入临时文件，并为 hdiutil、codesign、spctl、ditto 增加超时；超时会终止进程、卸载 DMG、清理临时文件并进入错误态。相关验证：Debug build 成功，113 个 XCTest 全部通过，UpdateService SwiftLint 0 violations。重新发布 Beta 后仍需在真实的 Beta2 安装包上验证完整下载→校验→替换→重启链路。

## 应用图标配置生成（AppIcon.appiconset） · 2026-08-18 22:32 CST · agent

（由 docs/开发记录.md 合并；其中的脚本路径已过时，以下是核对当前工程后的结论。）

macOS 应用的图标集在 `Light Stats/Assets.xcassets/AppIcon.appiconset`，`Contents.json` 使用 `idiom: "mac"`——`platform: "ios"` 对 macOS 应用无效。每个条目必须有 `filename` 字段，图标文件必须是 PNG。当前工程共 10 个条目，按 1x/2x 覆盖 16 → 1024：16(1x)、32(1x/2x)、64(2x@32)、128(1x/2x)、256(1x/2x)、512(1x/2x)、1024(2x@512)。

修改图标后必须 Clean Build（Cmd + Shift + K）再重新构建，否则可能沿用旧资源。生成方式：① 在线工具 appicon.co / makeappicon.com——上传 1024px 图标、选 macOS 平台一键出全套；② 本地 `sips -z` 从 1024 源图批量缩放（16/32/64/128/256/512/1024）后手写 Contents.json。sips 流程：`sips -z <h> <w> "$SOURCE" --out icon_<n>.png`。

## ScrollDirectionService 的 IOHID 改写机制与坑 · 2026-08-18 17:10 CST · agent

`ScrollDirectionService`（滚动方向反转 / 关加速度 / 触控板反转）是重建成本最高的服务之一：正确性依赖一堆无法从代码表面看出的私 API 行为，之前的踩坑记录散在代码注释里，这里收敛成结论。

**机制**：我们用 session 级 tap（`.cgSessionEventTap` + `.headInsertEventTap`）。开启 Natural Scrolling 后，滚动方向的「权威来源」是事件底层的 IOHIDEvent 浮点值，不是 CGEvent 的 delta 字段——只改 CGEvent 会被系统从 IOHID 重新派生覆盖、方向翻不动。所以反转必须 `CGEventCopyIOHIDEvent` 取出底层 IOHIDEvent，改写其 ScrollX/ScrollY 浮点，同时同步改写 CGEvent 三个 delta 字段。

**三个已验证的坑（不要回退）**：
1. **IOHID ABI**：64 位 Mac 上 IOHIDFloat 是 Double，`IOHIDEventGet/SetFloatValue` 必须按 Double 声明；按 Float 声明会读到错位垃圾值，方向静默失效。
2. **读-写顺序**：写任何字段前必须一次性读完所有原始 delta。设置 DeltaAxis 会让系统按固定倍率（约 8×）重算 PointDelta/FixedPt，边读边写会读到重算值、把方向二次翻回原样。
3. **IOHID 二次拷贝**：改完 CGEvent 字段后必须「重新」`CGEventCopyIOHIDEvent` 再写 IOHID——改 CGEvent 会重建底层 IOHIDEvent，沿用旧拷贝会落在脱钩对象上失效。

**关加速度的语义（对照开源定案）**：只归一化垂直 `DeltaAxis1`（行步进），`point/fixed/IOHID` 只做方向翻转、不归一化。之前试过把 `scrollLines/|line|` 套到所有字段，会把原始像素量一起缩放、手感发虚——这是 Scroll Reverser `discreteAdjust` 分支刻意避免的。`scrollLines` 独立于 `stepMultiplier`（不再叠乘），`stepMultiplier` 也不作用于连续设备（触控板/Magic Mouse 只做方向反转）。

**参考来源与边界**：反转照 Scroll Reverser `MouseTap.m`（同为 session tap），关加速度语义照 UnnaturalScrollWheels `ScrollInterceptor.swift`（HID 级 tap + `signum*scrollLines`）。注意 Scroll Reverser 源码里水平 IOHID 写入误用了垂直乘数 `vmul` 而非 `hmul`，这是它的 bug，不要抄——我们已用正确的 `hmul`。设备分类只用 `isContinuous`（与 UnnaturalScrollWheels 默认一致）；Scroll Reverser 用 gesture tap 数手指区分触控板 vs 连续鼠标的方案被否决（生命周期/权限/兼容风险大，且我们的设置把触控板/Magic Mouse 当同一组）。

**已补的健壮性**：tap 被系统禁用或睡眠唤醒后会自动恢复（`didWakeNotification` 立即 + 1 秒延迟重试；port 失效则在同线程重建 tap）。

**仍待真机验证**（无头环境测不了手感）：慢/快滚产生的 ±1/±2/±3/±5 归一化手感、触控板惯性阶段方向连续性、睡眠唤醒恢复、Logitech Options 等第三方驱动可能错误标记 continuous 的边界。

Popover 的视觉主角必须是健康分数、实时指标、状态和趋势；tab track、selected state、工具栏按钮、well 与 hover wash 只是辅助导航和交互反馈。它们不得成为 panel 最深、最亮、饱和度最高或对比最强的区域，否则会倒置信息层级并抢走 instrument data 的注意力。

选中态应依靠克制的字重变化、很轻的洗色或细指示线表达，不使用高对比实心舱、大面积深色轨道或高饱和渐变。这个原则适用于所有主题，不只 Sun Gold / Neon。允许 tab track 不等于允许它成为视觉板块；评审时必须把控件放回完整 panel 中比较注意力，而不能只看控件局部是否“好看”。

## 禁止内容暗板 / 阅读卡片 · 2026-08-18 15:35 CST · Grok

产品硬约束：任何主题都不得给 instrument 读数盖一层填色卡片、烟玻璃或「阅读板」来解决对比度。字直接坐在场景上。这条不只针对 Neon。

起因：Neon 配色改成暖金后，金字叠在 SunGold 高光上看不见，曾用 `surfaceFill` 深琥珀半透明板垫在 `PanelSection` 后面。用户明确否决，并要求写成全主题约束。Bento 卡片已删除，禁止以「阅读面」名义加回来。

允许：tab track、well（进度槽）、hover 浅洗。不允许：section / row / popover 本体的填色圆角底板。Neon 的 `surfaceFill` 必须保持 `.clear`。对比度只能靠墨水相对场景，不能靠加一层板。

Neon 后续补充：不要荧光。禁止高饱和高亮金 / 柠 / 青 / 粉，禁止文字和 sparkline 辉光。色板是哑光黄铜、赭石、铁锈，不是灯管。夜色酒吧可以保留灯管辉光，Neon 不行。

## 主题阵容收缩：Ash Veil 与 Bento 已删除 · 2026-08-18 · agent

产品决定删除 `ashVeil`（灰纱）与 `bento`（Bento 网格）两个主题，只剩 4 个可见预设：`glass`（默认）/ `film`（霓虹）/ `bar`（夜色酒吧）/ `noir`（墨夜），另有隐藏的 `dataPaper`。

- `bento` 的删除范围包括：`AppTheme.bento` case、`ThemeDefinition.bento`、`UITokens.bento`、`ThemeLayout.bento` 与 `usesBentoLayout` 布局分叉（现已不存在，全产品只有 instrument 布局）、`BentoCard` / `QuickStatCard` 组件、Overview / Cleanup 的 bento 分支、`docs/screenshots/bento/`。
- 设置窗的 `appThemed` 锁从 `.bento` 换成 `.glass`（同为 vibrant + 系统控件底，视觉等效）。
- 迁移行为：已存储的 `"ashVeil"` / `"bento"` 偏好经 `AppTheme.resolve` 回落到 `.noir`，有回归测试覆盖。
- 后续若再加主题，改 `ThemeDefinition` 组合表即可，业务视图（Overview / Cleanup / 行组件）已无布局分叉。

## 官方模型价格估算基准（pi） · 2026-08-17 13:38 CST · agent

为 pi 的 `~/.pi/agent/models.json` 配置成本估算时，采用官方上游公开价格作为参考，单位均为 USD / 1M tokens。当前配置使用的是 `https://api.shu.cool/v1` 中转，因此这些数字只用于 pi 的本地成本估算，不代表中转服务的实际扣费；中转价格需要另行确认。

- OpenAI 官方标准价：`gpt-5.6-sol` input 5 / output 30 / cacheRead 0.50 / cacheWrite 6.25；`gpt-5.6-terra` 2 / 12 / 0.20 / 2.50；`gpt-5.6-luna` 0.20 / 1.20 / 0.02 / 0.25；`gpt-5.5` 5 / 30 / 0.50 / 0。输入上下文超过 272K 时，分别使用长上下文价：Sol 10 / 45 / 1 / 12.5，Terra 4 / 18 / 0.40 / 5，Luna 0.40 / 1.80 / 0.04 / 0.50，GPT-5.5 10 / 45 / 1 / 0。
- DeepSeek 官方当前同时按高峰/非高峰计价：`deepseek-v4-flash` 非高峰 input 0.22 / cacheRead 0.007 / output 0.66，高峰 0.44 / 0.014 / 1.32；`deepseek-v4-pro` 非高峰 0.66 / 0.022 / 1.98，高峰 1.32 / 0.044 / 3.96。官方没有单独的 cacheWrite 价格，pi 中填 0。为避免低估，`models.json` 采用高峰价。
- xAI 官方标准价：`grok-4.5` input 2 / cacheRead 0.30 / output 6，`grok-4.6` 2 / 0.50 / 6；prompt 达到 200K 时使用长上下文价：Grok 4.5 为 4 / 0.60 / 12，Grok 4.6 为 4 / 1 / 12。两者均无单独 cacheWrite 价格，pi 中填 0。

价格来源：OpenAI <https://developers.openai.com/api/docs/pricing>；DeepSeek <https://api-docs.deepseek.com/quick_start/pricing>；xAI <https://docs.x.ai/developers/pricing>。价格可能变化，后续更新 `models.json` 前应重新核对官方页面。

## 主题以 ThemeDefinition 固定组合，不向用户暴露混搭 · 2026-08-16 17:01 · Grok

这条取代 2026-08-16 16:36「主题拆成 UITheme + BackgroundTheme 两个正交维度」。那次把界面和背景做成了可独立持久化的产品维度，并准备以后加背景选择器。产品决定不走这条路：用户仍然只看见 `glass / bento / film / noir` 四个预设，不出现背景选择或主题组合。

正确边界是：`AppTheme` 只是产品预设 ID；`ThemeDefinition` 是唯一组合入口，固定写出 `ui + background + layout`；`UITokens` 管文字 / surface / signal / divider / accent / 卡片与布局语义；`BackgroundConfiguration` 管 `glass / mesh / solid`、canvas、mesh 色、grain、dynamics；Film / Noir 光场是独立 Renderer。业务 View 只读解析结果，禁止 `theme == .film` / `theme == .noir`。`aurora` / `paper` 不再映射到 film，未知键回落到 noir。以后加第五个主题只改 `ThemeDefinition` 表，复用或新增内部能力，不改 Overview / Cleanup / 卡片，也不把组合能力做成设置项。

## 主题拆成 UITheme + BackgroundTheme 两个正交维度 · 2026-08-16 16:36 · Grok

`AppTheme` 不再同时拥有布局/配色和背景策略。它现在只是四个策展配对：`glass = glass UI + glass 背景`，`bento = bento UI + glass 背景`，`film = film UI + film 背景`，`noir = noir UI + noir 背景`。界面半边是 `UITheme`（layout、ink、surface、tab、signal；`usesBentoLayout` / `usesVibrantSurfaces` 留在这里）。背景半边是 `BackgroundTheme`（`glass / film / noir`，外加 `BackgroundKind`：`glass / mesh / solid`）。

`ThemeTokens` 只服务界面，禁止再长回 `usesGlass` / `usesMesh` / `canvas` / `meshBlob*` / `grainOpacity`。`ThemeBackgroundView` 只接收 `BackgroundTokens`，按 `kind` 选 renderer，按 `BackgroundTheme` 选 Film/Noir 光场，完全不知道 `UITheme` 或 `AppTheme`。设置仍用一个配对选择器，但已分别持久化 `settings.appTheme` 与 `settings.backgroundTheme`。读档时若已有独立的 background 键会尊重它（因此数据层已经能混搭）；改配对选择器仍会把 background 写回该配对，直到出现独立背景选择器。

以后加背景只新增 `BackgroundTheme` case + renderer + `BackgroundTokens` 工厂。不要回头改 Overview / Cleanup / 卡片，也不要把背景判断写回 `ThemeTokens.ui`。自由组合的下一步是设置里拆开两个选择器，并停止在 `appTheme.didSet` 里覆盖 `backgroundTheme`。

## macOS 26 Popover 滚轮隔离与动态主题基线 · 2026-08-10 10:48 · Codex

macOS 26 会让非透明 `NSPanel` 中未被 SwiftUI 子视图处理的滚轮事件继续落到桌面或下方窗口；用户报告 macOS 17 没有同样现象。稳定修复边界是在 `HitRetainingHostingView` 中保留现有 `hitTest` 全边界兜底，并在宿主层吸收最终未处理的 `scrollWheel`，而实际 `ScrollView` 等后代仍通过正常命中测试接收滚动。不要通过增加不透明绘制层、改变主题材质或强制 `.glass` 来解决事件穿透，因为事件隔离与视觉渲染必须互不耦合。

本次出现的“修复滚动后 Sun Gold 变粉”并非滚轮补丁改变颜色。第一张期望截图对应 `/Applications/Light Stats.app` 中约在提交 `49ae62a` 后构建的深色动态版本，而重新构建当前源码时启用了提交 `be82e1d` 的浅粉色静态 artwork 重构；该提交曾把 Sun Gold 从深色动态网格和浅色文字改为浅色静态象牙/玫瑰/珊瑚底，并将其首选配色方案从深色改为浅色。以后遇到“改一行后整个 UI 变样”时，应先比较正在运行的 App 构建来源、时间和源码提交，避免把重新构建显露出的既有提交误判为当前补丁的副作用。

当前确认的产品基线是保留 `49ae62a` 风格的深色动态 Sun Gold 与 Ink Night：动态网格、胶片颗粒、浅色文字，以及可持久化的 `filmGrainEnabled`、`filmLightFlow`、`noirGrainEnabled`、`noirLightFlow` 设置。主题应继续覆盖 Popover、About、Toast、Update 和权限提示；不得把这些窗口静默固定为默认玻璃主题。视觉回归应同时检查动态主题截图和 macOS 26 实机滚轮隔离，不能只凭编译成功判断。

## 历史归档 · 由 sessionlog 合并（2026-05-03 → 2026-07-12）

> 以下条目由已删除的 sessionlog.md 合并而来，保留原始时间与 agent。凡是与上方 2026-08 之后条目冲突的旧结论（主题阵容、默认主题、paper/aurora 映射等），以更新条目为准。滚动反转的 IOHID 改写机制见文首同主题条目，此处不重复。

## 打包 · 签名 · 公证全流程与 Secrets · 2026-05-03 · composer

发布链是「打 tag → CI → DMG → GitHub Release」，流程写在 `.github/workflows/release.yml` 与 `script/build.sh`。Release job 使用 `environment: APPLE`，敏感项集中在 Settings → Environments → APPLE；`GITHUB_TOKEN` 由 Actions 自动注入 `action-gh-release`，不用手动配置。

Secret 角色：`BUILD_CERTIFICATE_BASE64` = Developer ID Application `.p12` 的 Base64（CI 内 `base64 --decode` → `security import` 到临时钥匙串）；`P12_PASSWORD` = 导出 p12 时设的密码；`KEYCHAIN_PASSWORD` = 仅锁 CI 新建的临时钥匙串，与 Apple 账号无关；`APPLE_API_KEY_ID` = notarytool 的 `--key-id`，与 `AuthKey_<Key ID>.p8` 文件名一致；`APPLE_API_ISSUER_ID` = App Store Connect「用户与访问 → 密钥」页顶的 Issuer ID（口述常误说成 Issue ID）；`APPLE_API_KEY_BASE64` = `AuthKey_*.p8` 全文 Base64，脚本解码为 `build/api-key.p8`（chmod 600）。

公证开关：仅当 `APPLE_API_KEY_ID`、`APPLE_API_ISSUER_ID`、`APPLE_API_KEY_BASE64` 三者皆非空才 `NOTARIZATION_ENABLED=1`，否则跳过 notarytool/stapler。script/build.sh 流程：`CODE_SIGNING_ALLOWED=NO` 编出未签名 app → `codesign --deep --force --options runtime --timestamp`（Developer ID Application，entitlements 用 `LightStats.entitlements`）→ `hdiutil create` 打 DMG → 再签 DMG → `xcrun notarytool submit --wait`（--key-id / --issuer / --key 指向 p8）→ `stapler staple`。`DEVELOPER_ID` 环境变量可手写完整证书串覆盖 `find-identity` 自动解析（避免多机文案差异）。生成 Base64：`base64 -i Your.p12 | pbcopy`；若 CI 解码失败可先 `tr -d '\n'` 压成单行再贴 Secret。

## GitHub Release 签名失败：Development 证书 vs Developer ID · 2026-05-03 · composer

典型症状：`security import` 成功（1 identity imported），但 `security find-identity -v -p codesigning` 只列出 `Apple Development`；流水线用 `grep "Developer ID Application"` 断言时 grep 以 exit 1 收尾、整步失败——容易被误读成 Secret 丢了，实际是证书类型不匹配。`BUILD_CERTIFICATE_BASE64` 里若是 Apple Development 证书，只够 Debug 场景；Release 链路要求 Developer ID Application（商店外分发的 Mac App 对应的证书）。付费账号不会让钥匙串自动长出 Developer ID，Secret 齐全只保证「有东西导入」，不保证导入的是哪一种身份。

创建路径：developer.apple.com → Certificates → Software → **Developer ID Application**，Profile Type 选 **G2 Sub-CA**（当前 GitHub macos-latest 与常见 Xcode 选 G2；Previous 只留给必须兼容很老签名链的场景）。CSR 只是本机生成的请求数据，不带「Development 还是 Developer ID」标签，真正决定证书类型的是门户里选的模板。证书助理的菜单在屏幕最顶部系统菜单栏（钥匙串访问 → 证书助理 → 从证书颁发机构请求证书…），不在钥匙串窗口内部。

下载的 `.cer` 双击即可安装进登录钥匙串；「我的证书」里应看到 `Developer ID Application: …` 且展开下有专用密钥——只有证书没有私钥就无法导出可给 CI 用的 p12。导出：选中证书整行 → 文件 → 导出项目… → 个人信息交换 (.p12) → 设导出密码（即 `P12_PASSWORD`）。p12 内含私钥，Secret 文本与密码同时泄露等于泄露签名权；怀疑泄露须在 Apple 后台吊销该证书并换新 p12。若坚持私钥不出本机，只能改走自托管 Mac 本地签名（另一条运维路线）。本地自检：`security find-identity -v -p codesigning` 确认列表含 Developer ID Application 再推 tag。

## script/build.sh 错误日志透出与本地/CI Xcode 版本差 · 2026-05-03 19:59 · claude-opus-4-7

script/build.sh 把 xcodebuild 输出 tee 到 `build/xcodebuild.log`，失败时 grep `error:` 行打印出来再 exit（`BUILD_LOG`，现约 script/build.sh:88）。CI 失败先看这个文件里的 error 行。

环境差：本地是 Xcode 26 (SDK 26.1)，CI 是 Xcode 16.4。部署目标 macOS 14.6 / Swift 5 理论兼容，但若代码用了新 SDK 才有的 API（新版 SwiftUI / @Observable 新特性 / macOS 15+ 符号），16.4 会编译失败——要等下次 tag push 拿到具体 error 再修源码。日志里 `NSFileHandleOperationException: Broken pipe` 是 `xcodebuild -version | head -1` 的 SIGPIPE 噪音，与构建失败无关。

## 状态栏弹窗不显示：NSPanel canBecomeKey · 2026-06-07 11:13 · claude-opus-4-8

点击状态栏图标无弹窗、控制台刷 `makeKeyWindow … canBecomeKeyWindow NO` 警告。根因：`AppDelegate.setupPanel()` 的 NSPanel 用 `[.nonactivatingPanel, .fullSizeContentView]`，此类面板默认 `canBecomeKey` 返回 false → `makeKeyAndOrderFront` 拿不到 key 状态，又因 `hidesOnDeactivate = true`，`NSApp.activate` 触发的失活流程立刻把面板 orderOut → 表现为「没弹窗」。修法：新增 `KeyablePanel: NSPanel` 子类重写 `canBecomeKey` / `canBecomeMain` 返回 true（现位于 `Views/Popover/KeyablePanel.swift`）。控制台开头的 `GenerativeModelsAvailability` / `AFIsDeviceGreymatterEligible Missing entitlements` 是系统 Apple Intelligence 日志噪音，与此 bug 无关。

## Claude 用量隔夜必失败：token 永久缓存 + 401 跳过降级 · 2026-06-19 12:09 · claude-opus-4-8

现象：Claude 用量「放着不动隔天必显示获取失败」，定时器自动重试永不成功，只有重启 app 或手动重置缓存才恢复。根因是两个叠加：① OAuth access token 只活几小时（凭证 JSON `claudeAiOauth.expiresAt` 是毫秒 epoch，实测约 3h 窗口），CLI 会用 refreshToken 刷新并写回 Keychain，但 `ClaudeUsageService` 把 token 进程级永久缓存（`_cachedToken`）→ 菜单栏 app 常驻数天一直喂死 token → 永久 401；② `fetch()` 收到 `.tokenExpired` 直接 throw，跳过了写好的 Messages API + CLI-PTY 三层降级——而 CLI-PTY 兜底恰是唯一不依赖死 token 的真恢复路径，因果接反了。对照：`CodexUsageService` 一直是对的（每次现读凭证、401→重读比对→重试一次→CLI 兜底）。

修法：`.tokenExpired` 改走 `recoverFromExpiredToken()`（失效缓存→重读→token 真变了重试 API 一次→否则走 CLI-PTY）；token 缓存换成 `ClaudeTokenCache` actor（存 token + expiresAt，过期前 60s 自动失效，**保留 401 强制失效**——截断凭证/缺 expiresAt/提前吊销靠时间判断不出来）；`AIUsageMonitor.handle()` 过期且有旧快照时走 `.stale` 而非 `.error`，仅 `.credentialsMissing`（登出）报错；Gemini 同类轻症：catch `.tokenExpired` → `forceRefreshAccessToken()` 绕过过期时钟强制刷新重试一次。

注意：`type_body_length` 警告上限是 500 行（CLAUDE.md 里的 800 是 file_length，别混）；当初把 `CachedCredential` / `ClaudeTokenCache` / 凭证解析函数移到文件作用域（私有顶层，紧耦合 helper 豁免）就是为了把行数移出 enum body。弹窗安全：恢复路径坚持「先读文件 + `/usr/bin/security` 子进程」，不碰会弹授权框的 `SecItemCopyMatching`。此修复无法本机验证隔夜恢复——要等真实 token 过期才触发，最终判据是装新版放一夜看次日能否自愈。

## 常驻事件 tap 必须跑独立线程（滚动反转死机教训） · 2026-06-20 02:05 · claude-opus-4-8

ScrollDirectionService 刚上线时一滚动全系统卡死（触控板连带）。根因是架构性的：`.cgSessionEventTap` + `.defaultTap` 是会话级「主动」同步 tap，WindowServer 会同步等待回调返回才把滚动事件派发给任何 App；原实现把 run loop source 挂 `CFRunLoopGetCurrent()` = 主 RunLoop，而本 app 主线程每秒被 `SystemMonitor` 的 `proc_listallpids` + 逐进程 `task_info` 阻塞几十~几百 ms → tap 得不到服务 → 全系统滚动输入卡死。卡的是事件派发链路，不是翻转逻辑（所以只翻鼠标却连触控板一起卡）。

修法（架构约束，勿回退）：常驻 tap 必须放专用 `Thread`（`.userInteractive`）跑自己的 CFRunLoop，与主线程监控负载彻底解耦（Scroll Reverser / Mac Mouse Fix 的标准架构）。跨线程状态用 NSLock 守护；`while isRunning` + `CFRunLoopStop` 兜住「刚 start 又 stop」竞态，确保关开关时 tap 一定被 disable。权限先在主线程同步 `AXIsProcessTrusted` 检查，避免后台线程才发现失败再跨线程回传。KeyboardLockService 用主线程模式没事，是因为它只在 60s 清洁模式短暂存在；**常驻 tap 绝不能共用繁忙主 RunLoop**。

用户拍板的配置决策：水平反转 = 独立开关；阻尼 = 步长倍率 0.25×–3× 默认 1× 作用双轴；阻尼依附反转开关（tap 仅在「垂直 ∨ 水平反转」开启时运行，单独调倍率不启动 tap，设置里滑块在两个反转都关时禁用+淡化）。IOHID 改写机制与坑见文首「ScrollDirectionService 的 IOHID 改写机制与坑」。

## 发布灰度通道解耦：预发布 tag 隔离 + 版本号以 tag 为准 · 2026-06-20 10:05 · claude-opus-4-8

需求：打 tag 一定触发线上发布，但 beta 不能推给正式用户。关键事实：客户端 `UpdateService.fetchLatest()` 打的是 GitHub `/releases/latest`，该 endpoint 官方定义就是「最新的非 prerelease、非 draft release」，天然跳过 prerelease。解法是最小改动：release 流程按 tag 是否含连字符判定 prerelease（现 `release.yml` 由 prepare job 计算并输出 `PRERELEASE`，`action-gh-release` 传 `prerelease:`），`v1.6.0-beta.1` 这类 tag 照样签名 + 公证 + 传 DMG、可手动下载，但正式用户收不到。放弃过「双通道客户端开关」（过重）和 draft release（beta 测试者拿不到下载链接）两个方案。

版本号唯一真实来源是 git tag：`script/build.sh` 用 `MARKETING_VERSION="$VERSION"`（来自 `git describe --tags --exact-match`）覆盖工程值。`project.pbxproj` 里的 `MARKETING_VERSION = 1.0.2` 是本地 Debug 兜底，永远不要手改。

当时的 toolbar tooltip 重做（可复用的 SwiftUI 方案）：系统 `.help()` tooltip 弃用（延迟长、黄底不搭毛玻璃审美）；自定义 overlay 必须挂根层而非 header 子树——图标在 header 右上，tooltip 只能向下展开，一展开就进入 HealthCard 区域，挂 header 子树会被后绘制的内容盖住。方案：`ToolbarIconBoundsKey: PreferenceKey` 用 `.anchorPreference(value: .bounds)` 收集每个图标实测边界 → 根层 `.overlayPreferenceValue` + GeometryReader 用 `proxy[anchor]` 取 rect → `.position(x: rect.midX, y: rect.maxY + tooltipGap)` 居中贴图标下方；删光硬编码几何，唯一常量是间距。overlay 加 `.allowsHitTesting(false)`，`.onHover` 包 `withAnimation` 让淡入淡出生效。

## Finder 扩展状态探测与擦屏模式限便携机型 · 2026-06-29 11:10 · claude-opus-4-8

「访达右键菜单无效」根因排查结论：app 侧全部正常（appex 已签名/公证/被宿主签名封装、App Group 共享生效、CFMessagePort 宿主服务正常启动），真正缺失的是 **FinderSync 扩展没被系统 pkd 注册/启用**——`pluginkit -m -i cain.com.light-stats.FinderMenuExtension` 无匹配，统一日志里扩展进程零记录。注册是 OS（pkd）在 app 进 LaunchServices 并启动时自动做的，**没有公开 API 让 app 自己注册**；最可能诱因是 `/Applications` 正式版 + debug 版两份同 bundle id 同时在跑造成 pkd 注册冲突。

为此的产品改进：宿主新增 `FinderMenuHostService.extensionStatus()`（nonisolated static，跑 `pluginkit -m -i <id>` 解析首字符：`+`=启用，`-`/`?`=已注册未勾选，空=未注册），经 `FinderMenuConfigStore.extensionStatus`（@Published，onAppear 刷新）暴露给设置详情页显示状态行；配套 `Models/FinderExtensionStatus.swift` 枚举、`FinderMenuShared.extensionBundleID` 常量、四语言 `settings.finderMenu.status.*`。目的：用户开总开关后能看到「OS 层是否真启用」，不再静默无菜单。

擦屏模式限便携机型：新增 `Utilities/DeviceCapabilities.swift` 的 `isPortable`——**判据是有无内置电池**（IOKit 查 `AppleSmartBattery`），不是解析 `hw.model`（Apple Silicon 上 Mac mini 和 MacBook Air 都报 `MacXX,Y` 通用标识，前缀判断不可靠；有无电池在 Intel/AS、笔记本/台式机上都准）。擦屏入口用 `if DeviceCapabilities.isPortable` 包裹。

排查注意：zsh 里 `log` 被别名/函数拦截，要用 `/usr/bin/log` 绝对路径。

## 擦屏模式 KeyboardLockService 三处修复 · 2026-07-05 · claude-sonnet-4-6

**Bug 1 — 退出擦屏后键盘卡死：** `stop()` 先 `CGEvent.tapEnable(enable: false)` 但实例变量 `eventTap` 仍非 nil；系统投递 `.tapDisabledByTimeout` 时回调检查 `eventTap != nil` 又执行 `tapEnable(true)` 重新启用，随后 run loop source 被移除 → tap 处于「启用但无投递通道」状态 → 全系统键盘事件被拦截后丢弃。修法：先把 `eventTap`/`runLoopSource` 存局部变量并清空实例变量，再执行 disable/remove，确保回调不会误重新启用。

**Bug 2 — 功能键（亮度/音量/媒体）未被拦截：** mask 只覆盖 `keyDown`/`keyUp`/`flagsChanged`，但 Mac 顶排功能键走 `NX_SYSDEFINED`（type=14，`CGEventType` 枚举未包含，需用 `rawValue: 14` 构造）。修法：mask 加入 NX_SYSDEFINED，handle 中对该类型全量吞掉、不做 subtype 过滤（只吞 subtype=8 会因 NSEvent 转换失败或 subtype 差异漏过）。

**修复 3 — `passRetained` → `passUnretained`：** refcon == nil 的 guard fallback 分支误用 `passRetained(event)`，按 CGEvent 文档回调传入事件由调用方 retain/release，应放行而非额外 retain。Codex 建议的 `deinit { stop() }` 与保存创建时 RunLoop 两项被判断为过度防御，未采用。

安全设计不变：60s 倒计时 timer 与 tap 解耦，tap 静默失败 timer 仍会退出，用户不可能被卡住；「End」按钮是唯一手动出口。

## FinderMenu beta 5：菜单上下文缓存 + IPC 失败 toast + 双扩展残留 · 2026-07-07 18:00 · pi-coding-agent

beta 4 的问题：子菜单点击时上下文丢失（menu(for:) 里能拿到 targetedURL，但 submenu action 触发时已失效）。修法：FinderMenuCommand 在 menu(for:) 阶段缓存 paths + container，runAction() 不再重新查询 FIFinderSyncController。

DeepSeek review 后补的两个修复：

- **P1 — IPC 发送失败不再静默。** 扩展侧两次发送均失败后写 App Group pending failure；宿主 start() 时检查并 toast（四语言 `findermenu.toast.delayedFailure`），然后清除。用户点菜单没反应必须给反馈，不能只写 log.error。
- **P2 — `directory(for:)` 不再盲目信任 container。** 原来无条件信任 Finder 的 targetedURL() 返回值是目录；现在加 isDirectory 检查，不是目录就取 parent。

排障教训：清空权限/App Group/UserDefaults 后出现鸡生蛋问题——扩展读到 App Group `isEnabled()=true` 出了菜单，但 Host 的 SettingsManager 从自己 UserDefaults 读到 false → CFMessagePort 从未启动 → 点击菜单完全沉默；pluginkit 里残留两份扩展注册（Debug 1.0.2 + /Applications 1.9.0-beta.5）时 Finder 右键出现两个菜单项。

**尚未从代码层面修的问题：** Host 启动时应把 App Group 的 `isEnabled()` 作为权威来源，而不是只信自己的 UserDefaults——否则一旦 UserDefaults 和 App Group 不一致（清数据、迁移、备份恢复都可能触发），就会出现「菜单可见但点击无效」的静默失败。修复起点可以是 start() 时 consumePendingFailure，更根本的是 syncFinderMenuService() 启动时读 App Group 的值纠正 UserDefaults。

## Finder 文件面板挂起滚动/手势 tap 服务 · 2026-07-10 · pi-coding-agent

现象：Finder 菜单设置里的文件选择面板（NSOpenPanel）以 sheet 打开时，ScrollDirectionService / TitlebarGestureService 的 CGEventTap 仍在拦截系统级滚动事件 → 面板内滚动异常（反向滚动仍生效、标题栏手势误触发）。

修法：FinderMenuConfigStore 在 present() 中发送 willPresent / didDismiss 通知，AppDelegate 观察这两个通知并调用 `setSuspended(true/false)` 挂起/恢复两个事件 tap 服务。setSuspended 时 ScrollDirectionService 原样放行事件，TitlebarGestureService 重置手势状态并隐藏预览。影响范围：AppDelegate、FinderMenuConfigStore、ScrollDirectionService、TitlebarGestureService 四个文件，仅在 Finder 文件面板打开期间生效。

## 多主题 UI + Reicon SVG + 胶片外观旋钮 + 设置窗解耦 · 2026-07-12 · grok-4.5

> 本条目描述 2026-07-12 状态，主题阵容部分已被下方更新条目取代：当时是 film（冷启动默认）/ bento / glass / noir 四主题、paper/aurora 读档映射 film；现为 glass（默认）/ film / bar / noir + 隐藏 dataPaper，bento 与 ashVeil 已删除（见 2026-08-18「主题阵容收缩」），未知键回落 noir（见 2026-08-16「ThemeDefinition 固定组合」）。以下其余事实经核对仍有效。

- **Reicon Outline SVG**：从 [dqev/reicon](https://github.com/dqev/reicon) 导出到 `Resources/Icons/`（cpu / gpu / memory / network / proxy / disk / temperature / processes），`SVGIcon` / `AppSVGIcon` 用 NSImage 解码 + template 着色（零第三方）；`ATTRIBUTION.txt` 标注 MIT + Solar/Zappicon 上游；负载/风扇/上下行等仍用 SF Symbol。
- **设置窗固定系统白底**，不跟随展示主题：`.appThemed(.glass)`（当时是 `.bento`，同为 vibrant + 系统控件底、视觉等效，2026-08-16 改锁为 glass）+ `controlBackgroundColor`，不挂 ThemeBackgroundView；主题只作用 Popover / About / Toast / Update。
- **主题选择器精简**：去掉迷你预览画布，只保留标题 + 副标题 + 选中描边（更省高、更像系统设置）。
- **胶片专属外观**（仅 `appTheme == .film` 时 UI 露出）：`filmGrainEnabled`（默认 true，关 = 只留光影无胶片 grit）+ `filmLightFlow`（0–1，0 = 静止，0.5 = 产品默认，1 = 更快更大幅漂移）；初版幅度太小且设置页无反馈 → 加大漂移与平移，并内嵌实时 mesh 预览。
- 历史上有一版「设置也随主题」后改回固定白底，最终行为是固定白底。

## 胶片/暗黑视觉模型与单参数光影动力学 · 2026-07-12 19:18 · codex

film（胶片棕）是暖色模型：深棕底 + 珊瑚/酒红径向光团、两条倾斜 S 形光带、奶油 bloom，文字高对比暖白，状态色金黄/鼠尾草绿/琥珀/珊瑚。noir（墨夜）是冷色模型：近黑底 + 冰蓝/灰紫纵向光柱、窄光带、顶部微光，文字冷白，状态色薄荷/冰蓝/紫。

颗粒：确定性双尺度噪声纹理——256px 高频颗粒以 soft-light 混合，128px body 颗粒以 overlay 混合；每进程只生成一次并缓存（现为 `Views/Theme/Background/Shared/GrainTextureCache` + `GrainOverlay`）；film 额外加暖色 tint，noir 保持中性。

外观设置最终收敛为「光影动态」单参数（现持久化为 `filmLightFlow` / `noirLightFlow` 0–1，配 `filmGrainEnabled` / `noirGrainEnabled`）。**旧方案曾分别暴露流速、水平位置、垂直位置三个控件，已废弃并从持久化键移除，不要恢复。** 结构：`ThemeAppearanceConfiguration` 只向背景传颗粒状态与 dynamics 强度，`ThemeAppearancePresetConfiguration` 负责可传参档位的实际数值，渲染组件不直接读 `SettingsManager.shared`。

动态算法（现位于 `Views/Theme/Background/Scenes/`：film = SunGoldScene、noir = InkNightScene，系数合并时已对照代码确认仍在）：单一 dynamics 先经 `smoothstep(u) = u²(3-2u)` 映射生成基础相位；相位叠加 0.19 与 0.37 两个低频正弦带，形成连续的轻微加速与减速；二维位置是准周期李萨如轨迹——X 由 0.61 与 1.17 倍频正弦叠加，Y 由 0.43 倍频余弦与 0.83 倍频正弦叠加；相位不取模，避免非整数倍频在周期边界跳帧；改变档位时保留相位锚点，因此速度变化不会让光场瞬移；静止档冻结相位并把轨迹位移归零。

film 使用横向更宽、纵向较克制的轨迹（斜向胶片光洗感）；noir 独立系数，低档收敛中心、活跃档最大横向跨度约画面宽 29%、纵向约 25%，让冷色光柱明显巡游。全幅基础渐变固定不参与平移，只移动超尺寸光团与光带，所以轨迹到边缘不会露出底层空隙；阅读 veil 仅小幅跟随轨迹以维持文字对比度。bento/glass 无自定义 mesh、颗粒或动态光场，跟随系统明暗外观。

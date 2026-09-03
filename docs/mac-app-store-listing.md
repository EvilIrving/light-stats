# Mac App Store 上架操作指南

配套设计：`docs/app-store-edition.md`  
截图成品：`docs/app-store-screenshots/mas-1440x900/`  
工程分支：`feature/app-store`（**暂不合** `main`；直销 DMG 继续原流程）

商店版：**免费**（无 IAP、无激活码 UI）。直销继续 Developer ID + 公证 + R2/GitHub 自更新。

---

## 0. 两件事

1. 商店包用分支 `feature/app-store` + scheme **`Light Stats AppStore`**，不必先合 main。  
2. 商店签名用 **Apple Distribution**，不是 Developer ID Application（后者只给直销 DMG）。

本机已确认有：

```text
Apple Distribution: TIANBAO DONG (QZZ878S3NS)
```

```bash
security find-identity -v -p codesigning | grep -i Distribution
```

---

## 1. Identifiers（Developer 后台）

必须与工程字符串完全一致：

| 类型 | Identifier |
|---|---|
| 主 App ID | `cain.com.light-stats` |
| Finder 扩展 App ID | `cain.com.light-stats.FinderMenuExtension` |
| App Group | `QZZ878S3NS.com.light-stats.shared` |

Team：`QZZ878S3NS`。

步骤摘要：

1. [Identifiers](https://developer.apple.com/account/resources/identifiers/list) 先搜 `light-stats`，已有则只核对。  
2. 缺则先建 **App Groups** → `QZZ878S3NS.com.light-stats.shared`（TeamID 前缀，不要 `group.`）。  
3. 建主 App ID（Explicit）→ 开 **App Groups** → Configure 勾上上述 Group。  
4. 建扩展 App ID → 同样挂同一 Group。  
5. Xcode 两 Target（`Light Stats` / `FinderMenuExtension`）Team + Automatic Signing，Capabilities 里 Group 字符串一致。

ASC「新建 App」只能选用已注册的 Explicit App ID；**注册 Identifiers ≠ 新建 ASC 应用**。

---

## 2. App Store Connect 新建 App

1. [App Store Connect](https://appstoreconnect.apple.com) → 我的 App → + → 新建 App  
2. 平台 **macOS**；名称 Light Stats；Bundle ID `cain.com.light-stats`；SKU 如 `light-stats-mac`  
3. 定价：**免费**，不设 IAP  
4. 隐私政策：`https://evilirving.github.io/light-stats/`（或站点 privacy 锚点）  
5. 年龄分级、App Privacy 问卷如实填写（不追踪；诊断本地；出口节点仅用户开启时联网；无账号）

---

## 3. Archive / 上传

Scheme：`Light Stats AppStore` · Configuration：`AppStore`

```bash
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats AppStore" \
  -configuration AppStore \
  MARKETING_VERSION=1.9.2 \
  CURRENT_PROJECT_VERSION=100 \
  -archivePath build/LightStats-AppStore.xcarchive \
  archive
```

或 Xcode：**Product → Archive → Distribute App → App Store Connect → Upload**。  
签名页必须是 **Apple Distribution**，不要出现 Developer ID。

上传后：ASC → TestFlight → 等处理；补出口合规（通常「仅 HTTPS」选否专用加密）。

---

## 4. 版本号

| | 含义 | 注意 |
|---|---|---|
| `MARKETING_VERSION` | 对外版本，如 `1.9.2` | 与产品线对齐；**不要用** pbxproj 里的 `1.0.2` |
| `CURRENT_PROJECT_VERSION` | Build，如 `100` | ASC 内必须单调递增 |

`project.pbxproj` 的 `MARKETING_VERSION = 1.0.2` / Build `2` 是**本地 Debug 回退**；直销正式版由 git tag + `script/build.sh` 的 `MARKETING_VERSION=$VERSION` 覆盖。商店 Archive **必须显式设** Version/Build。

正式上架营销版本避免带 `beta`。

---

## 5. 本地自测（上传前）

```bash
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats AppStore" \
  -configuration AppStoreDebug \
  -derivedDataPath build/DerivedData-AppStore \
  build

open "build/DerivedData-AppStore/Build/Products/AppStoreDebug/Light Stats.app"
```

核对：监控正常；无更新/激活/AI/窗口管理/输入设备；About 无检查更新；默认路径无 Accessibility 弹窗；Sandbox = Yes。

```bash
codesign -d --entitlements - \
  "build/DerivedData-AppStore/Build/Products/AppStoreDebug/Light Stats.app" | head -30
```

---

## 6. 截图与图标

- 成品：`docs/app-store-screenshots/mas-1440x900/`（1440×900，16:10）  
- 源裁切：`docs/app-store-screenshots/source/`  
- 规格也可：1280×800 / 1440×900 / 2880×1800，整套统一  
- 只拍商店版有的功能；总览图勿含 Pro / 保持唤醒 / 清洁模式（应用 **AppStore** 包重截更稳）  
- 图标：`Light Stats/Assets.xcassets/AppIcon.appiconset/1024.png`

---

## 7. 审核备注（可粘贴）

```text
Light Stats (Mac App Store) is a FREE menu-bar system monitor.

This build is sandboxed and intentionally smaller than our direct-download edition:
- Included: CPU/GPU/memory/disk/network/battery, health score, process list, themes, optional Finder extension, optional exit-node lookup.
- Not included: self-update, activation codes, SMC fan/temp sensors, AI CLI usage scraping, window snapping, scroll reverse, cleaning mode, keep-awake/virtual display, DDC brightness.

No Accessibility permission is required for the default monitoring path.
Exit-node geo lookup is OFF by default; enable in Settings → Monitoring.
Finder extension is OFF by default; user enables in Settings and System Settings → Login Items & Extensions.

LSUIElement=YES (menu bar agent). Open via the menu bar status item.
```

---

## 8. TestFlight 内测

1. ASC → TestFlight → macOS 构建处理完成  
2. 内部测试加人（须为团队成员）  
3. Mac 安装 **TestFlight** → 接受 → 安装  
4. 与直销同 Bundle ID，勿两套并存；内测前卸掉 DMG 版更干净  

直销完整包仍：`https://download.onecat.dev/stable`（或 beta）。

---

## 9. 正式提交与通过后

1. 选 build → 填元数据/截图/审核备注 → 提交审核  
2. 通过后手动或自动发售  
3. **有商店链接后再**改官网 / README 徽章；当前 `docs/index.html` 仍只推 DMG  
4. 商店包禁止自更新；直销继续 tag → DMG 流程  

---

## 工程开关速查

| | Direct | App Store |
|---|---|---|
| Scheme | `Light Stats` | `Light Stats AppStore` |
| Config | `Debug` / `Release` | `AppStoreDebug` / `AppStore` |
| Flag | _(无)_ | `APP_STORE` |
| Entitlements | `LightStats.entitlements` | `LightStats-AppStore.entitlements` |
| 能力表 | 全功能 | 见 `AppDistribution` / `docs/app-store-edition.md` |

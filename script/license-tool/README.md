# license-tool — 离线激活码发码器

Light Stats 高级功能（首个为「找到我的鼠标」）的离线激活码工具。私钥只存在于发码机器，
App 内置公钥做本地校验（Ed25519，`CryptoKit`，零第三方依赖，零网络请求）。

## 构建与测试

```bash
swift build
swift test
```

## 命令

```bash
# 1) 生成密钥对（只需一次，默认写到 ~/.light-stats-license/）
swift run license-tool generate-keypair

# 2) 发码
swift run license-tool issue --private-key ~/.light-stats-license/private.key \
    --owner "购买者姓名/邮箱"

# 3) 验码（客服/自测用）
swift run license-tool verify --public-key ~/.light-stats-license/public.key \
    --code "LS1-XXXX-…"
```

## 安全须知（务必阅读）

- **私钥永不提交、永不进 App。** `~/.light-stats-license/private.key` 生成时已设为
  `chmod 600`。公钥 `public.key` 是公开的，已嵌入 App（`Light Stats/Services/LicenseValidator.swift`）。
- **备份私钥。** 丢失后，旧码仍可由 App 内现有公钥验证，但无法继续签发匹配该公钥的
  新码。若改用新密钥，App 需在过渡期同时信任旧、新公钥，不能直接替换后让旧码失效。
- `generate-keypair` 发现目标目录已有 `private.key` 或 `public.key` 时会拒绝覆盖；轮换密钥前
  必须显式移走旧文件并妥善备份。
- **激活码可分享。** 码不绑定机器（产品决策）；签名保证无法伪造，但拿到码的人都能用。
- **开源可被 fork 移除门禁。** 这是「开源 + 激活码」模式的固有代价，已接受。

## 发新功能

- App 侧：`LicensePayload.Feature`（`Light Stats/Models/LicensePayload.swift`）加 case。
- 发码：`issue --feature <key>`（默认 `findMouse`）。
- 老版本 App 容忍未知功能键：只授予它认识的特性。

## 与 App 的格式同步

`Sources/license-tool/LicenseCodec.swift` 与 `Light Stats/Services/LicenseCodec.swift`
互为镜像，`Sources/license-tool/Payload.swift` 与 `Light Stats/Services/LicenseValidator.swift`
的 JSON 载荷形状一致。**两侧任何一处改动，必须同步另一侧**，并跑：
- App 测试 `LightStatsTests/LicenseValidatorTests.testGoldenFixtureValidates`（钉死线格式）
- 本包 `swift test`

## 为什么退出码可能是 139（历史坑）

main.swift 的顶层 `let` 按声明顺序立即初始化。`defaultKeyDirectory` 必须声明在
使用它的命令 switch **之前**，否则读到未初始化内存直接段错误。保持现在的声明顺序即可。

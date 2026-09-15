# Wins 拆解档案 · 索引

对 `/Applications/Wins.app` 3.5.1 与 `~/Downloads/Wins-latest.dmg` 的完整反向工程记录。
目的：**实现阶段不出现意外**——每一个功能、每一个可调参数、每一个系统依赖、每一个已知坑，都在这里。

## 档案构成

| 文件 | 内容 | 什么时候看 |
|------|------|-----------|
| `01-package-inventory.md` | 安装包里每一个文件的清单与用途 | 想知道某样东西从哪来 |
| `02-feature-matrix.md` | 全部功能 × 设置键 × 默认值 × 我们的现状 | 排优先级 |
| `03-type-map.md` | 190 个类 + 598 个 ivar + 265 个 Swift 类型的字段表 | **写代码时对着抄字段名** |
| `04-behaviour-spec.md` | 触发判定、动画参数、状态机、时间常数的实现规格 | 实现某个功能前 |
| `05-keys-assets-strings.md` | UserDefaults 键、日志子系统、reason code、内置黑名单、资产、SF Symbol | 建数据模型 / 做设置项 |
| `06-substitutions-and-traps.md` | 私有 API、系统依赖、OS 版本分支、已知冲突 | 动手前必须过一遍 |
| `07-interaction-repair.md` | 用户实测后的交互修复、录屏对照、性能证据与验收边界 | 继续实现或判断完成度时 |
| `assets/` | 从 Wins.app 抽出的交互参考素材（图标、布局 tile、演示中间帧、命名色、字符串） | 对着做 UI / 动效时 |

主文档（差距诊断 + 路线图）在上一层：`docs/wins-window-management-teardown.md`。

## 方法与可信度

三类证据，混合使用。下面的结论都标注了类别。

**A 类 · 直接读出（事实）**
- ObjC 运行期元数据（`otool -oV`）：类名、父类、ivar 名字与**声明顺序**（注意：其 `offset` / `size` 两列对 Swift 类不可靠，见 `03-type-map.md` 开头的说明）
- Swift 反射元数据（`__TEXT,__swift5_types` + `__swift5_fieldmd` + `__swift5_reflstr`）：类型名、字段名、字段类型
- 链接框架表（`otool -L`）、entitlements（`codesign -d`）、所有 Info.plist
- 字符串表（`__objc_methname`、`__cstring`、`__oslogstring`）
- **`~/Library/Preferences/cools.wins.main.plist`** —— Wins 在这台机器上跑过，真实默认值全在这里
- `Contents/Resources/` 下的全部资产（22 段功能演示 MP4、Assets.car、prefPane、nib）

**B 类 · 结构性推断（可信，已标注）**
- 从 ivar 组合推出的行为（例：`timer` + `startTime` + `onFrameUpdate` + `didFinish` ⇒ Timer 驱动的逐帧插值器）
- 从语义与命名推出的字段种类（`startFrame` / `targetFrame` 是 CGRect、`completion` 是闭包、`didFinish` 是 Bool）

**C 类 · 未解析（明确标出）**
- 类型列里的 `—`：该字段的类型引用是间接的（stdlib 泛型 / 闭包），没解析出来。**字段名与声明顺序仍然可信**，只是类型未知。
- 具体数值常量（例：`topOverflowTolerance` 到底是 8 还是 12）：ivar 只有名字，值在运行期。已实测的默认值来自 plist；其余只能给"存在这个参数"而给不出数值。

## 复现命令

```bash
# 安装包
hdiutil attach ~/Downloads/Wins-latest.dmg -nobrowse -readonly

# 瘦身出 arm64 切片（后续全部基于这个文件）
lipo -thin arm64 "/Applications/Wins.app/Contents/MacOS/Wins" -output /tmp/Wins_arm64

# 类 / ivar / 方法签名
otool -oV /tmp/Wins_arm64 > /tmp/wins_objc.txt

# Swift 类型与字段（section 起始 addr 减 0x100000000 即文件偏移）
otool -l /tmp/Wins_arm64 | grep -A4 __swift5_types      # addr 0x100237d54 size 0x628
otool -l /tmp/Wins_arm64 | grep -A4 __swift5_fieldmd    # addr 0x10023106c size 0x5e68
otool -l /tmp/Wins_arm64 | grep -A4 __swift5_reflstr    # addr 0x10022b300 size 0x5d6b
otool -l /tmp/Wins_arm64 | grep -A4 __cstring           # addr 0x100245770 size 0xf469

# 真实默认值与布局 JSON
defaults export cools.wins.main - | plutil -convert json -o - - | python3 -m json.tool

# 权限
codesign -d --entitlements - "/Applications/Wins.app"

# 功能演示视频（22 段）
ls "/Applications/Wins.app/Contents/Resources/Wins.prefPane/Contents/Resources/"*.mp4
```

解析 Swift 反射段的要点（`__swift5_types` 里每条是 int32 相对偏移）：

```
entry          = types_addr + 4*i
descriptor     = entry + int32(entry)
kind           = u32(descriptor) & 0x1F      # 16=class 17=struct 18=enum
name           = cstr(descriptor+8 + int32(descriptor+8))
fieldDescriptor= descriptor+16 + int32(descriptor+16)
  fd+8  = u16 kind，fd+10 = u16 recordSize，fd+12 = u32 numFields
  record r: rec = fd+16 + r*recordSize
            mangledTypeName = cstr(rec+4 + int32(rec+4))
            fieldName       = cstr(rec+8 + int32(rec+8))
```

同一地址体系下，`__objc_methname` 里的字符串用 `va - 0x100000000` 直接取文件偏移即可。

# script/ — 仓库脚本统一目录

所有可执行脚本（构建、压测、本地化校验、工程维护）统一放在这里。
脚本内部已 `cd` 回仓库根目录，从任意位置以 `./script/<name>` 调用即可。

| 脚本 | 作用 |
|------|------|
| `build.sh` | 发布 DMG 构建（版本号来自 git tag；CI 在 `build.yml` / `release.yml` 中调用） |
| `debug-run.sh` | 一键构建 Debug 并启动：kill 旧实例 → xcodebuild → open |
| `skillmesh.sh` | 把 `.agents/skills` 的 Skill 以软链同步到 Claude / Codex / Cursor / Pi / Grok |
| `validate_localization.sh` | 校验 en / zh-Hans / ja / ko 四份 `Localizable.strings` key 一致（CI 在 `quality.yml` 中调用） |
| `gen-changelog.sh` | 从 git 提交记录生成 CHANGELOG.md（CI 在 `release.yml` 中调用） |
| `add_test_target.rb` | pbxproj 重建后重新接线 XCTest target（`ruby script/add_test_target.rb`） |
| `add_finder_extension_target.rb` | pbxproj 重建后重新接线 FinderSync extension target |
| `stress-cpu.sh [秒数]` | 打满所有 CPU 核心（压测健康分） |
| `stress-memory.sh [GB] [秒数]` | 分配并触碰大块内存（压测健康分） |

## 压测脚本

用于验证健康分（`HealthScoreService`）在系统真正受压时能否如期掉分。
评分逻辑见 `CLAUDE.md` 的 **Health Score** 一节（含瓶颈封顶机制）。

| 脚本 | 作用 | 影响的健康分维度 |
|------|------|------------------|
| `stress-cpu.sh [秒数]` | 打满所有 CPU 核心 | `cpu`、`load`，连带 `temperature`（升温/降频） |
| `stress-memory.sh [GB] [秒数]` | 分配并触碰大块内存 | `memory`（内存压力 + swap） |

## 用法

```bash
./script/stress-cpu.sh 60          # CPU 满载 60 秒
./script/stress-memory.sh          # 默认占用物理内存的 90%，45 秒
./script/stress-memory.sh 28 30    # 指定占用 28GB、30 秒
```

压测期间，在菜单栏**按住 ⌥Option 点图标**可把面板快照导出到 `/tmp/popover-overview.png`
（仅 DEBUG 构建提供此入口），用于对比分数变化。

## 注意

- 两个压测脚本都注册了清理 trap：`Ctrl-C` 或脚本结束会立即终止 worker / 释放内存。
- `stress-memory.sh` 占用接近物理内存时系统会明显卡顿，**可能有 App 被系统终止**，
  运行前请保存工作。Apple Silicon 会压缩非活跃页，占用不够高时压力等级仍是「正常」、
  swap 为 0——这是预期，说明内存维度不会因为「占用高但不颠簸」而误报。

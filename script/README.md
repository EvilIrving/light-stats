# script/ — 压测脚本

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

- 两个脚本都注册了清理 trap：`Ctrl-C` 或脚本结束会立即终止 worker / 释放内存。
- `stress-memory.sh` 占用接近物理内存时系统会明显卡顿，**可能有 App 被系统终止**，
  运行前请保存工作。Apple Silicon 会压缩非活跃页，占用不够高时压力等级仍是「正常」、
  swap 为 0——这是预期，说明内存维度不会因为「占用高但不颠簸」而误报。

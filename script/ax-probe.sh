#!/bin/bash
set -euo pipefail

# ax-probe 的入口：按需编译并缓存二进制，再把参数原样交给它。
#
# 编译一次放在 build/ 下，源码变了自动重编；调用方永远只写 ./script/ax-probe.sh。
# 另外把"读诊断日志"也收在这里：验收与排查都靠 windowManagement 事件，之前每次都在
# 命令行里现写一段 python 去解析，同样是一次性劳动。
#
#   ./script/ax-probe.sh <command> [args]      → 交给 Swift 探针（见 ./script/ax-probe.sh help）
#   ./script/ax-probe.sh mark                  → 打印当前日志字节偏移，之后用它取增量
#   ./script/ax-probe.sh journal <mark> [动作…] → 打印自 mark 起的 windowManagement 事件
#   ./script/ax-probe.sh journal-path          → 打印今天的日志路径
#
# 需要辅助功能权限（系统设置 → 隐私与安全性 → 辅助功能）。

cd "$(dirname "$0")/.."

SOURCE="script/ax-probe/main.swift"
BINARY="build/ax-probe"
JOURNAL_DIR="$HOME/Library/Application Support/Light Stats/Diagnostics"

if [ ! -x "$BINARY" ] || [ "$SOURCE" -nt "$BINARY" ]; then
    mkdir -p build
    if ! swiftc -O "$SOURCE" -o "$BINARY" 2>&1 | head -20; then
        echo "❌ ax-probe 编译失败" >&2
        exit 1
    fi
fi

command="${1:-help}"

case "$command" in
mark)
    latest="$(ls -t "$JOURNAL_DIR"/diagnostics-v3-*.jsonl 2>/dev/null | head -1 || true)"
    [ -n "$latest" ] || { echo "0"; exit 0; }
    stat -f%z "$latest"
    ;;
journal-path)
    ls -t "$JOURNAL_DIR"/diagnostics-v3-*.jsonl 2>/dev/null | head -1
    ;;
journal)
    shift
    mark="${1:-0}"; shift || true
    latest="$(ls -t "$JOURNAL_DIR"/diagnostics-v3-*.jsonl 2>/dev/null | head -1 || true)"
    [ -n "$latest" ] || exit 0
    python3 - "$latest" "$mark" "$@" <<'PY'
import sys, json
path, mark = sys.argv[1], int(sys.argv[2])
wanted = set(sys.argv[3:])
with open(path) as handle:
    handle.seek(mark)
    for line in handle:
        try:
            event = json.loads(line)
        except Exception:
            continue
        if event.get("category") != "windowManagement":
            continue
        action = event.get("action", "")
        if wanted and action not in wanted:
            continue
        fields = {}
        for key, value in event.get("fields", {}).items():
            fields[key] = value.get("value") if isinstance(value, dict) else value
        print(event.get("timestamp", "")[11:19], action, json.dumps(fields, ensure_ascii=False, sort_keys=True))
PY
    ;;
*)
    exec "$BINARY" "$@"
    ;;
esac

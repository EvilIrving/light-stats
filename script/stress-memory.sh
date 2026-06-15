#!/usr/bin/env bash
#
# stress-memory.sh — 分配并触碰大块内存，逼出内存压力 / swap，验证健康分的内存维度。
#
# 用法:
#   ./script/stress-memory.sh [GB] [秒数]    # 默认 占用 = 物理内存的 90%，持续 45 秒
#
# 注意: Apple Silicon 会压缩非活跃页，需占用接近物理内存才会真正触发压力 / swap，
#       届时系统会明显卡顿、可能有 App 被系统终止。请保存好工作再运行。
# Ctrl-C 可随时中止并立即释放内存。

set -euo pipefail

PHYS_BYTES="$(sysctl -n hw.memsize)"
PHYS_GB=$(( PHYS_BYTES / 1024 / 1024 / 1024 ))
DEFAULT_GB=$(( PHYS_GB * 9 / 10 ))

GB="${1:-$DEFAULT_GB}"
DURATION="${2:-45}"

py_pid=""
cleanup() {
  [ -n "$py_pid" ] && kill "$py_pid" 2>/dev/null || true
  echo "已释放内存。"
}
trap cleanup EXIT INT TERM

echo "内存压测: 物理 ${PHYS_GB}GB，目标占用 ${GB}GB，持续 ${DURATION}s"

/usr/bin/python3 - "$GB" "$DURATION" <<'EOF' &
import sys, time
gb = int(sys.argv[1]); hold = int(sys.argv[2])
GB = 1024 * 1024 * 1024
PAGE = 16384
chunks = []
try:
    for i in range(gb):
        b = bytearray(GB)
        for off in range(0, GB, PAGE):  # 触碰每一页，强制驻留
            b[off] = 1
        chunks.append(b)
        print(f"allocated {i + 1}/{gb} GB", flush=True)
    print(f"holding {hold}s under pressure...", flush=True)
    time.sleep(hold)
finally:
    chunks = None
EOF
py_pid="$!"

# 观察压力等级（1=正常 2=警告 4=危急）与 swap
while kill -0 "$py_pid" 2>/dev/null; do
  printf 'pressure=%s  ' "$(sysctl -n kern.memorystatus_vm_pressure_level)"
  sysctl -n vm.swapusage
  sleep 5
done

wait "$py_pid" 2>/dev/null || true
echo "内存压测结束。"

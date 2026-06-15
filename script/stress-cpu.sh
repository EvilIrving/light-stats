#!/usr/bin/env bash
#
# stress-cpu.sh — 把所有 CPU 核心打满，用于验证健康分的 CPU / 负载维度与瓶颈封顶。
#
# 用法:
#   ./script/stress-cpu.sh [秒数]      # 默认 60 秒
#
# 压测期间在菜单栏按住 ⌥Option 点图标可导出面板快照到 /tmp（仅 DEBUG 构建）。
# Ctrl-C 可随时中止并清理所有 worker。

set -euo pipefail

DURATION="${1:-60}"
CORES="$(sysctl -n hw.ncpu)"
WORKERS=$((CORES * 2))   # 略多于核数，确保运行队列堆积、LoadAvg 升高

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  echo "已清理 ${#pids[@]} 个 worker。"
}
trap cleanup EXIT INT TERM

echo "CPU 压测: ${CORES} 核 → ${WORKERS} 个忙等 worker，持续 ${DURATION}s"
for _ in $(seq 1 "$WORKERS"); do
  ( end=$((SECONDS + DURATION)); while [ "$SECONDS" -lt "$end" ]; do :; done ) &
  pids+=("$!")
done

# 周期性打印负载，便于观察
end=$((SECONDS + DURATION))
while [ "$SECONDS" -lt "$end" ]; do
  printf 'loadavg: %s\n' "$(sysctl -n vm.loadavg | tr -d '{}')"
  sleep 5
done

wait
echo "CPU 压测结束。"

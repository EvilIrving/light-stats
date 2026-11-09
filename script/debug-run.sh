#!/bin/bash
# 用 Debug 构建重放一次「拖拽授权引导」。
#
# 正式入口只在一个权限缺失时出现，所以在已经授权的机器上这个流程根本走不到。启动参数
# `--permission-guide-demo [accessibility|screenRecording]` 让引导照常出现并停在那儿，
# 不监听授权结果，用来检查飞行、停靠和返回。
#
# 注意：Debug 包是临时签名，它的 TCC 身份和 /Applications 里那份 Developer ID 包不同。
# 要验证「真的能授权」，用 ./script/local-run.sh 装签名包，再带同样的参数启动。
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Light Stats"
DERIVED="build/DerivedData"
PANE="${1:-accessibility}"

usage() {
    cat <<'EOF'
用法: ./script/debug-run.sh [accessibility|screenRecording]

构建 Debug 版并带 `--permission-guide-demo <pane>` 启动，重放拖拽授权引导。
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

echo "🛑 退出旧实例..."
pkill -9 -x "$APP_NAME" 2>/dev/null || true

xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Debug \
    -derivedDataPath "$DERIVED" build

echo "🚀 启动 Debug 版并重放权限引导（${PANE}）..."
open "$DERIVED/Build/Products/Debug/$APP_NAME.app" --args --permission-guide-demo "$PANE"

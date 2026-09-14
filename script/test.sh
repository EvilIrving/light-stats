#!/bin/bash
# 跑单元测试（与 CI 的 quality gate 同款），跑完清掉本次构建留下的重复 Finder 扩展注册。
#
# 为什么需要后面那一步：`xcodebuild test` 会把 Debug 版 App 构建到 DerivedData 并作为
# TEST_HOST 启动；它内嵌的 FinderMenuExtension.appex 带着同一个 bundle id，会被 pkd 注册。
# 而 Debug 版的版本号取的是 pbxproj 里写死的 fallback（1.0.2），比本地 Release 包的
# 1.0.0-dev 还高——于是系统里同时存在多份同名插件，Finder 右键菜单可能落到错误的那一份。
# 本项目实际被这个坑过，所以测完必须剪掉。
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
EXTENSION_ID="cain.com.light-stats.FinderMenuExtension"
KEEP_PREFIX="/Applications/"

usage() {
    cat <<'EOF'
用法: ./script/test.sh [xcodebuild test 的额外参数]

例如:
  ./script/test.sh
  ./script/test.sh -only-testing:LightStatsTests/HealthScoreServiceTests
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' "$@"

# 只保留 /Applications 下那一份注册，其余同名副本一律注销。
stale="$(
    pluginkit -m -A -D -v -p com.apple.FinderSync 2>/dev/null \
        | grep "$EXTENSION_ID" \
        | awk -F'\t' '{print $NF}' \
        | grep -v "^$KEEP_PREFIX" \
        || true
)"

if [ -z "$stale" ]; then
    echo "✅ 插件注册干净：只有 ${KEEP_PREFIX} 下那一份"
    exit 0
fi

while IFS= read -r path; do
    [ -n "$path" ] || continue
    echo "🧹 注销重复注册: $path"
    pluginkit -r "$path" || true
done <<< "$stale"

pluginkit -m -A -D -v -i "$EXTENSION_ID" 2>/dev/null || true

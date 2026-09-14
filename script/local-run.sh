#!/bin/bash
set -e

# 本地跑一份**和线上发布同构**的签名 Release：同一个 Developer ID、同一套 entitlements、
# 同一个 bundle id，只是不出 DMG、不公证，直接覆盖 /Applications 后启动。
#
# 所以辅助功能、输入监控、Finder 扩展沿用已授权的那份身份，不用重开权限；
# 也不需要另开一个 Debug / 测试宿主。版本号跟线上同源，都是 git 推出来的：
# 不在 tag 上就是 `<最近tag>-dev.<领先提交数>`。
cd "$(dirname "$0")/.."

APP_NAME="Light Stats"
INSTALL_PATH="/Applications/$APP_NAME.app"

if [ -z "${DEVELOPER_ID:-}" ]; then
    DEVELOPER_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Developer ID Application: [^"]*' | head -1 || true)"
fi
if [ -z "${DEVELOPER_ID:-}" ]; then
    echo "❌ 覆盖 $INSTALL_PATH 需要 Developer ID Application 证书。"
    echo "   没有它，系统会把新包当成另一个 App，辅助功能等权限要重新开。"
    exit 1
fi
export DEVELOPER_ID

echo "🛑 退出旧实例..."
pkill -9 -x "$APP_NAME" 2>/dev/null || true

SKIP_DMG=1 SKIP_NOTARIZATION=1 INSTALL_TO_APPLICATIONS=1 ./script/build.sh

echo "🚀 打开 $INSTALL_PATH..."
open "$INSTALL_PATH"
echo "✅ 完成"

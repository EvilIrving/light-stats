#!/bin/bash
set -e

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
APP_NAME="Light Stats"
DERIVED="build/DerivedData"
APP_PATH="$DERIVED/Build/Products/Debug/$APP_NAME.app"

cd "$(dirname "$0")/.."

# 退出正在运行的实例，避免打开旧构建
echo "🛑 退出旧实例..."
pkill -9 -f "$APP_NAME" 2>/dev/null || true

echo "🔨 构建 Debug..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
    -configuration Debug -derivedDataPath "$DERIVED" build

echo "🚀 打开 $APP_NAME..."
open "$APP_PATH"
echo "✅ 完成"

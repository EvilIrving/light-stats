#!/bin/bash
set -e

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
APP_NAME="Light Stats"

# ── 版本号 ──────────────────────────────────────────────
if [ -n "$VERSION" ]; then
    echo "📌 使用环境变量版本号: $VERSION"
elif git describe --tags --exact-match 2>/dev/null; then
    VERSION=$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//')
    echo "📌 使用 git tag 版本号: $VERSION"
else
    VERSION="1.0.0-dev"
    echo "📌 使用默认版本号: $VERSION"
fi
BUILD_DIR="build"
OUTPUT_DIR="$BUILD_DIR/output"
LOG_FILE="$BUILD_DIR/build.log"
DMG_DIR="$BUILD_DIR/dmg_temp"
DMG_FILE="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"
ENTITLEMENTS="Light Stats/LightStats.entitlements"

# ── 签名凭据（通过环境变量传入）─────────────────────────
# DEVELOPER_ID   - 证书身份，如 "Developer ID Application: Your Name (TEAMID)"
# APPLE_ID       - Apple ID 邮箱
# APPLE_PASSWORD - App 专用密码（https://appleid.apple.com → App 专用密码）
# APPLE_TEAM_ID  - 团队 ID（如 QZZ878S3NS）
# 以上任一项为空，则跳过对应签名/公证步骤。
SKIP_SIGN=false
SKIP_NOTARIZE=false

if [ -z "${DEVELOPER_ID:-}" ]; then
    echo "⚠️  未设置 DEVELOPER_ID 环境变量，将跳过代码签名。"
    SKIP_SIGN=true
fi
if [ -z "${APPLE_ID:-}" ] || [ -z "${APPLE_PASSWORD:-}" ] || [ -z "${APPLE_TEAM_ID:-}" ]; then
    echo "⚠️  未设置 APPLE_ID / APPLE_PASSWORD / APPLE_TEAM_ID，将跳过公证。"
    SKIP_NOTARIZE=true
fi

echo ""

# ── 检查 Xcode ──────────────────────────────────────────
echo "🔍 检查 Xcode 环境..."
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误: 未找到 xcodebuild。请确保已安装 Xcode 并设置了命令行工具。"
    exit 1
fi
xcodebuild -version
echo ""

# ── 清理 & 构建 ─────────────────────────────────────────
echo "🧹 清理旧构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "🔨 开始构建 (详细日志详见 $LOG_FILE)..."
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO > "$LOG_FILE" 2>&1

echo "📦 创建输出目录..."
mkdir -p "$OUTPUT_DIR"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$OUTPUT_DIR/"
chmod +x "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "✅ App 构建完成！"
echo "📍 App 位置: $OUTPUT_DIR/$APP_NAME.app"
echo ""

# ── 代码签名 ────────────────────────────────────────────
if [ "$SKIP_SIGN" = false ]; then
    echo "✍️  签名 App (Hardened Runtime)..."
    codesign --deep --force --verify --verbose \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$OUTPUT_DIR/$APP_NAME.app"

    echo "✅ App 签名完成。"
    echo "🔍 验证签名..."
    codesign --verify --deep --strict --verbose=1 "$OUTPUT_DIR/$APP_NAME.app"
    spctl --assess --verbose=1 --type execute "$OUTPUT_DIR/$APP_NAME.app" 2>&1 || true
    echo ""
else
    echo "⏭️  跳过代码签名（DEVELOPER_ID 未设置）。"
    echo ""
fi

# ── 创建 DMG ────────────────────────────────────────────
echo "📀 创建 DMG 安装包..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

cp -R "$OUTPUT_DIR/$APP_NAME.app" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_FILE"
rm -rf "$DMG_DIR"

echo "✅ DMG 创建完成。"
echo "📍 DMG 位置: $DMG_FILE"
echo ""

# ── 签名 DMG ────────────────────────────────────────────
if [ "$SKIP_SIGN" = false ]; then
    echo "✍️  签名 DMG..."
    codesign --force --verify --verbose \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$DMG_FILE"
    echo "✅ DMG 签名完成。"
    echo ""
fi

# ── 公证 ────────────────────────────────────────────────
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "📤 提交公证 (可能需要几分钟)..."
    xcrun notarytool submit "$DMG_FILE" \
      --apple-id "$APPLE_ID" \
      --password "$APPLE_PASSWORD" \
      --team-id "$APPLE_TEAM_ID" \
      --wait

    echo ""
    echo "🔖 装订公证票据..."
    xcrun stapler staple "$DMG_FILE"
    echo "✅ 公证 + 装订完成。"
    echo ""
else
    echo "⏭️  跳过公证（凭据未完整提供）。"
    echo ""
fi

# ── 最终摘要 ────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 全部完成！"
echo "📍 App:  $OUTPUT_DIR/$APP_NAME.app"
echo "📍 DMG:  $DMG_FILE"
echo "📋 DMG 大小: $(du -h "$DMG_FILE" | cut -f1)"
if [ "$SKIP_SIGN" = false ]; then
    echo "🔐 签名状态: 已签名 (Hardened Runtime)"
else
    echo "🔐 签名状态: 未签名"
fi
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "🛡️  公证状态: 已公证 + 已装订"
else
    echo "🛡️  公证状态: 未公证"
fi
echo ""
echo "📖 使用方式:"
echo "   DEVELOPER_ID='Developer ID Application: ...' \\"
echo "   APPLE_ID='your@email.com' \\"
echo "   APPLE_PASSWORD='xxxx-xxxx-xxxx-xxxx' \\"
echo "   APPLE_TEAM_ID='QZZ878S3NS' \\"
echo "   ./build.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

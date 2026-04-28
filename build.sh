#!/bin/bash
set -e

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
APP_NAME="Light Stats"

# 版本号
if [ -n "$VERSION" ]; then
    echo "📌 版本号: $VERSION"
elif git describe --tags --exact-match 2>/dev/null; then
    VERSION=$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//')
    echo "📌 版本号: $VERSION (from git tag)"
else
    VERSION="1.0.0-dev"
    echo "📌 版本号: $VERSION (default)"
fi

BUILD_DIR="build"
OUTPUT_DIR="$BUILD_DIR/output"
DMG_DIR="$BUILD_DIR/dmg_temp"
DMG_FILE="$OUTPUT_DIR/${APP_NAME}-${VERSION}.dmg"
ENTITLEMENTS="Light Stats/LightStats.entitlements"

# 从 keychain 提取 Developer ID 证书身份（CI 已在上一步导入，本机则直接读取登录 keychain）
DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Developer ID Application: [^"]*' | head -1 || true)}"
[ -n "${DEVELOPER_ID:-}" ] && echo "🔐 $DEVELOPER_ID"

echo ""
echo "🔍 Xcode 版本: $(xcodebuild -version | head -1)"
echo ""

# 构建
echo "🔨 构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

mkdir -p "$OUTPUT_DIR"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$OUTPUT_DIR/"
chmod +x "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
echo "✅ $OUTPUT_DIR/$APP_NAME.app"

# 签名 App
if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "✍️  签名..."
    codesign --deep --force --verify \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$OUTPUT_DIR/$APP_NAME.app"
fi

# 创建 DMG
echo "📀 创建 DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$OUTPUT_DIR/$APP_NAME.app" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG_FILE" -quiet
rm -rf "$DMG_DIR"

# 签名 DMG
if [ -n "${DEVELOPER_ID:-}" ]; then
    codesign --force --verify \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$DMG_FILE"
fi
echo "✅ $DMG_FILE"

# 公证
if [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ] && [ -n "${APPLE_API_KEY_BASE64:-}" ]; then
    echo "📤 公证..."
    API_KEY_FILE="$BUILD_DIR/api-key.p8"
    echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"

    xcrun notarytool submit "$DMG_FILE" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      --key "$API_KEY_FILE" \
      --wait

    rm -f "$API_KEY_FILE"
    xcrun stapler staple "$DMG_FILE"
    echo "✅ 公证完成"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 $DMG_FILE ($(du -h "$DMG_FILE" | cut -f1))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

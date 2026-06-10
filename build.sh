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
DMG_BACKGROUND="packaging/dmg-background.png"
DMG_RW_FILE="$BUILD_DIR/${APP_NAME}-${VERSION}-rw.dmg"
ENTITLEMENTS="Light Stats/LightStats.entitlements"
NOTARIZATION_ENABLED=0
if [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER_ID:-}" ] && [ -n "${APPLE_API_KEY_BASE64:-}" ]; then
    NOTARIZATION_ENABLED=1
fi
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
MAIN_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"

verify_signed_runtime() {
    local target="$1"
    local label="$2"
    local details

    codesign --verify --strict --verbose=2 "$target"
    details="$(codesign -dv --verbose=4 "$target" 2>&1)"
    echo "$details" | grep -E "Authority=|Runtime Version|Timestamp|flags=" || true

    if ! echo "$details" | grep -q "flags=.*runtime"; then
        echo "❌ $label 缺少 Hardened Runtime。"
        exit 1
    fi

    if ! echo "$details" | grep -q "^Timestamp="; then
        echo "❌ $label 缺少安全时间戳。"
        exit 1
    fi
}

# 从 keychain 提取 Developer ID 证书身份（CI 已在上一步导入，本机则直接读取登录 keychain）
DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Developer ID Application: [^"]*' | head -1 || true)}"
[ -n "${DEVELOPER_ID:-}" ] && echo "🔐 $DEVELOPER_ID"

if [ "$NOTARIZATION_ENABLED" -eq 1 ] && [ -z "${DEVELOPER_ID:-}" ]; then
    echo "❌ 公证需要 Developer ID Application 证书，但当前 keychain 中未找到可用签名身份。"
    echo "请先在 CI 中导入 Developer ID Application 证书，或通过 DEVELOPER_ID 指定完整签名身份。"
    exit 1
fi

echo ""
echo "🔍 Xcode 版本: $(xcodebuild -version | head -1)"
echo ""

# 构建
echo "🔨 构建..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

BUILD_LOG="$BUILD_DIR/xcodebuild.log"
set +e
xcodebuild build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
if [ "$BUILD_STATUS" -ne 0 ]; then
    echo ""
    echo "❌ Build failed (exit $BUILD_STATUS). Errors:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    grep -E "error:|: error |FAILED" "$BUILD_LOG" || tail -80 "$BUILD_LOG"
    exit "$BUILD_STATUS"
fi

mkdir -p "$OUTPUT_DIR"
cp -R "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" "$OUTPUT_DIR/"
chmod +x "$MAIN_BINARY"
echo "✅ $APP_PATH"

# 签名 App
if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "✍️  签名..."
    codesign --deep --force --verify \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$APP_PATH"
    codesign --verify --strict --deep --verbose=2 "$APP_PATH"
    verify_signed_runtime "$APP_PATH" "App bundle"
    verify_signed_runtime "$MAIN_BINARY" "主二进制文件"
elif [ "$NOTARIZATION_ENABLED" -eq 1 ]; then
    echo "❌ 公证已启用，但 App 未签名。"
    exit 1
fi

# 创建 DMG
echo "📀 创建 DMG..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_PATH" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"
mkdir -p "$DMG_DIR/.background"
cp "$DMG_BACKGROUND" "$DMG_DIR/.background/background.png"
rm -f "$DMG_RW_FILE" "$DMG_FILE"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_DIR" -ov -format UDRW "$DMG_RW_FILE" -quiet

MOUNT_DIR="$(mktemp -d "/tmp/${APP_NAME// /_}.XXXXXX")"
hdiutil attach "$DMG_RW_FILE" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

# Try to configure DMG appearance; fail gracefully in CI environments
set +e
osascript <<EOF
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 540}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {180, 210}
    set position of item "Applications" of container window to {480, 210}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
set -e

hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR"
hdiutil convert "$DMG_RW_FILE" -format UDZO -imagekey zlib-level=9 -o "$DMG_FILE" -quiet
rm -rf "$DMG_DIR"
rm -f "$DMG_RW_FILE"

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
    NOTARY_SUBMIT_LOG="$BUILD_DIR/notarytool-submit.log"
    NOTARY_DETAIL_LOG="$BUILD_DIR/notarytool-log.json"
    echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"

    set +e
    xcrun notarytool submit "$DMG_FILE" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      --key "$API_KEY_FILE" \
      --wait 2>&1 | tee "$NOTARY_SUBMIT_LOG"
    NOTARY_STATUS=${PIPESTATUS[0]}
    set -e

    SUBMISSION_ID="$(sed -n 's/^[[:space:]]*id: //p' "$NOTARY_SUBMIT_LOG" | tail -1)"
    SUBMISSION_RESULT="$(sed -n 's/^[[:space:]]*status: //p' "$NOTARY_SUBMIT_LOG" | tail -1)"

    if [ "$NOTARY_STATUS" -ne 0 ] || [ "$SUBMISSION_RESULT" != "Accepted" ]; then
        echo ""
        echo "❌ 公证失败${SUBMISSION_RESULT:+: $SUBMISSION_RESULT}"
        if [ -n "$SUBMISSION_ID" ]; then
            echo "📄 获取公证详情: $SUBMISSION_ID"
            xcrun notarytool log "$SUBMISSION_ID" \
              --key-id "$APPLE_API_KEY_ID" \
              --issuer "$APPLE_API_ISSUER_ID" \
              --key "$API_KEY_FILE" \
              "$NOTARY_DETAIL_LOG" || true
            [ -f "$NOTARY_DETAIL_LOG" ] && cat "$NOTARY_DETAIL_LOG"
        else
            cat "$NOTARY_SUBMIT_LOG"
        fi
        rm -f "$API_KEY_FILE"
        exit 1
    fi

    rm -f "$API_KEY_FILE"
    xcrun stapler staple "$DMG_FILE"
    echo "✅ 公证完成"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 $DMG_FILE ($(du -h "$DMG_FILE" | cut -f1))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

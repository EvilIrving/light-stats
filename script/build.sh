#!/bin/bash
set -e

# 脚本统一放在 script/ 下，切回仓库根目录再跑，相对路径不变。
cd "$(dirname "$0")/.."

PROJECT="Light Stats.xcodeproj"
SCHEME="Light Stats"
APP_NAME="Light Stats"

# 版本号 —— 发布产物的唯一真源。
# 优先级：外部 VERSION（release.yml 从 git tag `vX.Y.Z` 解析）> HEAD 正好在 tag 上 → 用 tag
#        > HEAD 领先最近一个 tag → `<tag>-dev.<领先提交数>`（本地开发包）
#        > 仓库一个 tag 都没有 → 1.0.0-dev。
# 下方 xcodebuild 用 MARKETING_VERSION=$VERSION 覆盖，所以 DMG/About 显示的版本始终跟 git 走。
# 注意：pbxproj 里写死的 MARKETING_VERSION = 1.0.2 只对直接 xcodebuild（不经本脚本）生效，
# 是有意保留的 fallback，不跟 tag 同步、不影响发布，无需每次发版去改它。
# local-run.sh 走本脚本：Release + Developer ID，覆盖 /Applications。
if [ -n "${VERSION:-}" ]; then
    echo "📌 版本号: $VERSION（外部传入）"
elif git describe --tags --exact-match >/dev/null 2>&1; then
    VERSION=$(git describe --tags --exact-match 2>/dev/null | sed 's/^v//')
    echo "📌 版本号: $VERSION (from git tag)"
elif git describe --tags --long >/dev/null 2>&1; then
    # 不在 tag 上：最近 tag + 领先提交数，例如 v1.9.4-4-g1abe5a2 → 1.9.4-dev.4。
    # 不能写死一个占位版本：本地包会永远显示 1.0.0-dev，既比 pbxproj 的 fallback（1.0.2）低、
    # 又和已发布版本完全脱节。版本号反着排，系统就会挑错副本（pkd / LaunchServices 都按版本比较）。
    DESCRIBE="$(git describe --tags --long --dirty 2>/dev/null)"
    BASE="$(printf '%s' "$DESCRIBE" | sed 's/^v//; s/-[0-9][0-9]*-g[0-9a-f]*.*$//')"
    AHEAD="$(printf '%s' "$DESCRIBE" | sed -n 's/.*-\([0-9][0-9]*\)-g[0-9a-f].*/\1/p')"
    VERSION="${BASE}-dev.${AHEAD:-0}"
    case "$DESCRIBE" in *-dirty) VERSION="${VERSION}.dirty" ;; esac
    echo "📌 版本号: $VERSION (领先 ${BASE} ${AHEAD:-0} 个提交)"
else
    VERSION="1.0.0-dev"
    echo "📌 版本号: $VERSION (仓库无 tag)"
fi

BUILD_DIR="build"
OUTPUT_DIR="$BUILD_DIR/output"
DMG_DIR="$BUILD_DIR/dmg_temp"
DMG_FILE="$OUTPUT_DIR/Light-Stats-${VERSION}.dmg"
DMG_BACKGROUND="design/dmg-background.png"
DMG_RW_FILE="$BUILD_DIR/Light-Stats-${VERSION}-rw.dmg"
ENTITLEMENTS="Light Stats/LightStats.entitlements"
FINDER_EXTENSION_ENTITLEMENTS="FinderMenuExtension/FinderMenuExtension.entitlements"
SKIP_SIGNING="${SKIP_SIGNING:-0}"
SKIP_DMG="${SKIP_DMG:-0}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-0}"
NOTARIZATION_ENABLED=0
if [ "$SKIP_SIGNING" != "1" ] \
    && [ "$SKIP_NOTARIZATION" != "1" ] \
    && [ -n "${APPLE_API_KEY_ID:-}" ] \
    && [ -n "${APPLE_API_ISSUER_ID:-}" ] \
    && [ -n "${APPLE_API_KEY_BASE64:-}" ]; then
    NOTARIZATION_ENABLED=1
fi
INSTALL_PATH="/Applications/$APP_NAME.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
MAIN_BINARY="$APP_PATH/Contents/MacOS/$APP_NAME"
FINDER_EXTENSION_PATH="$APP_PATH/Contents/PlugIns/FinderMenuExtension.appex"
APP_NOTARY_ARCHIVE="$BUILD_DIR/${APP_NAME}-${VERSION}.zip"

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

notarize_file() {
    local target="$1"
    local label="$2"
    local log_name="$3"
    local submit_log="$BUILD_DIR/notarytool-${log_name}-submit.log"
    local detail_log="$BUILD_DIR/notarytool-${log_name}-log.json"
    local submission_id
    local submission_result
    local notary_status

    echo "📤 公证 $label..."
    set +e
    xcrun notarytool submit "$target" \
      --key-id "$APPLE_API_KEY_ID" \
      --issuer "$APPLE_API_ISSUER_ID" \
      --key "$API_KEY_FILE" \
      --wait 2>&1 | tee "$submit_log"
    notary_status=${PIPESTATUS[0]}
    set -e

    submission_id="$(sed -n 's/^[[:space:]]*id: //p' "$submit_log" | tail -1)"
    submission_result="$(sed -n 's/^[[:space:]]*status: //p' "$submit_log" | tail -1)"

    if [ "$notary_status" -ne 0 ] || [ "$submission_result" != "Accepted" ]; then
        echo ""
        echo "❌ $label 公证失败${submission_result:+: $submission_result}"
        if [ -n "$submission_id" ]; then
            echo "📄 获取公证详情: $submission_id"
            xcrun notarytool log "$submission_id" \
              --key-id "$APPLE_API_KEY_ID" \
              --issuer "$APPLE_API_ISSUER_ID" \
              --key "$API_KEY_FILE" \
              "$detail_log" || true
            [ -f "$detail_log" ] && cat "$detail_log"
        else
            cat "$submit_log"
        fi
        rm -f "$API_KEY_FILE" "$APP_NOTARY_ARCHIVE"
        exit 1
    fi
}

# 从 keychain 提取 Developer ID 证书身份（CI 已在上一步导入，本机则直接读取登录 keychain）。
# 普通 CI 显式设置 SKIP_SIGNING=1，确保 runner 即使意外存在证书也只生成未签名产物。
if [ "$SKIP_SIGNING" = "1" ]; then
    DEVELOPER_ID=""
    echo "🔓 已显式禁用签名与公证"
else
    DEVELOPER_ID="${DEVELOPER_ID:-$(security find-identity -v -p codesigning 2>/dev/null | grep -o 'Developer ID Application: [^"]*' | head -1 || true)}"
    [ -n "${DEVELOPER_ID:-}" ] && echo "🔐 $DEVELOPER_ID"
fi

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
  MARKETING_VERSION="$VERSION" \
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

# 中间产物不能留在仓库里：pkd 会扫描 build/ 下的 .appex，未签名、未沙盒的版本
# 带着同一个 bundle id 会被判为 "mis-configured plugin"（plug-ins must be sandboxed），
# 从而牵连 /Applications 里那份正式包，Finder 扩展会静默不出菜单。
# 只保留 $OUTPUT_DIR 下已签名的成品，中间 .app / .appex 一律删除。
rm -rf "$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" \
       "$BUILD_DIR/DerivedData/Build/Products/Release/FinderMenuExtension.appex"

# 签名 App
if [ -n "${DEVELOPER_ID:-}" ]; then
    echo "✍️  签名..."
    codesign --force --verify \
      --options runtime \
      --entitlements "$FINDER_EXTENSION_ENTITLEMENTS" \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$FINDER_EXTENSION_PATH"
    codesign --force --verify \
      --options runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$DEVELOPER_ID" \
      --timestamp \
      "$APP_PATH"
    codesign --verify --strict --deep --verbose=2 "$APP_PATH"
    verify_signed_runtime "$FINDER_EXTENSION_PATH" "FinderSync 扩展"
    verify_signed_runtime "$APP_PATH" "App bundle"
    verify_signed_runtime "$MAIN_BINARY" "主二进制文件"
elif [ "$NOTARIZATION_ENABLED" -eq 1 ]; then
    echo "❌ 公证已启用，但 App 未签名。"
    exit 1
fi

# 先单独公证并 stapled App，再把它装进 DMG。旧版更新器会直接对挂载后的
# App 执行 Gatekeeper 校验；App 自带票据后，即使 Apple 公证服务不可达也能离线通过。
if [ "$NOTARIZATION_ENABLED" -eq 1 ]; then
    rm -f "$APP_NOTARY_ARCHIVE"
    ditto -c -k --keepParent "$APP_PATH" "$APP_NOTARY_ARCHIVE"
    API_KEY_FILE="$BUILD_DIR/api-key.p8"
    echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    notarize_file "$APP_NOTARY_ARCHIVE" "App" "app"
    rm -f "$API_KEY_FILE"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"
    rm -f "$APP_NOTARY_ARCHIVE"
    echo "✅ App 公证完成"
fi

if [ "$INSTALL_TO_APPLICATIONS" = "1" ]; then
    if [ -z "${DEVELOPER_ID:-}" ]; then
        echo "❌ 覆盖 $INSTALL_PATH 需要 Developer ID Application 签名，否则辅助功能等权限对不上已授权的生产包。"
        exit 1
    fi
    echo "📦 覆盖 $INSTALL_PATH..."
    pkill -9 -x "$APP_NAME" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x "$APP_NAME" >/dev/null || break
        sleep 0.2
    done
    rm -rf "$INSTALL_PATH"
    ditto "$APP_PATH" "$INSTALL_PATH"
    echo "✅ 已安装 $INSTALL_PATH"
fi

if [ "$SKIP_DMG" = "1" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📍 $APP_PATH"
    if [ "$INSTALL_TO_APPLICATIONS" = "1" ]; then
        echo "📍 $INSTALL_PATH"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 0
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

# NOTE: do NOT pass -nobrowse here. With -nobrowse the volume mounts but Finder
# refuses to see it, so the AppleScript below fails with -1728 and the layout /
# background .DS_Store is never written. Let it mount under /Volumes so Finder can
# style it.
MOUNT_DIR="/Volumes/$APP_NAME"
hdiutil attach "$DMG_RW_FILE" -quiet
# Give Finder a moment to register the freshly mounted volume.
sleep 2

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

# Mark housekeeping items invisible so they never show even when a user has
# "show hidden files" toggled on. These are dot-files (hidden by default); .fseventsd
# is regenerated by macOS on every mount so deleting it is pointless. chflags is
# best-effort: the volume may be read-only and must never abort the build.
chflags hidden "$MOUNT_DIR/.background" "$MOUNT_DIR/.fseventsd" 2>/dev/null || true

hdiutil detach "$MOUNT_DIR" -quiet
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

# DMG 也单独公证并 stapled，供 Gatekeeper 首次打开镜像时离线验证。
if [ "$NOTARIZATION_ENABLED" -eq 1 ]; then
    API_KEY_FILE="$BUILD_DIR/api-key.p8"
    echo "$APPLE_API_KEY_BASE64" | base64 --decode > "$API_KEY_FILE"
    chmod 600 "$API_KEY_FILE"
    notarize_file "$DMG_FILE" "DMG" "dmg"
    rm -f "$API_KEY_FILE"
    xcrun stapler staple "$DMG_FILE"
    xcrun stapler validate "$DMG_FILE"
    echo "✅ DMG 公证完成"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📍 $DMG_FILE ($(du -h "$DMG_FILE" | cut -f1))"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#!/bin/bash
# 生成官网社交分享预览图 `website/social-preview.png`（1200×630）。
#
# 为什么要有这个脚本：`website/index.html` 的 og:image / twitter:image 指向这张图，
# 而 GitHub Pages 只发布 `website/` 下的文件——图片缺失时，任何分享链接的卡片都是空白。
# 卡片按官网自身的视觉规范生成（见 website/DESIGN.md），所以用官网的调色板与真实截图，
# 而不是另画一张风格无关的图。
#
# 用无头 Chrome 渲染：它用的是系统字体与真实 CSS 排版，不需要在 repo 里放设计工具。
# 需要 Google Chrome 已安装；否则脚本报错退出，不会留下半成品。
set -euo pipefail
cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT="website/social-preview.png"
SHOT="website/screenshots/ink-night/popover-overview.png"

if [ ! -x "$CHROME" ]; then
    echo "❌ 未找到 Google Chrome：$CHROME"
    exit 1
fi
[ -f "$SHOT" ] || { echo "❌ 缺少截图：$SHOT"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SHOT_ABS="$(cd "$(dirname "$SHOT")" && pwd)/$(basename "$SHOT")"

cat > "$TMP/card.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<style>
  :root {
    --bg: oklch(98.5% 0.004 255);
    --surface: oklch(99.6% 0.002 255);
    --ink: oklch(22% 0.012 260);
    --muted: oklch(52% 0.016 260);
    --faint: oklch(68% 0.012 260);
    --line: oklch(91% 0.006 260);
    --live: oklch(62% 0.15 150);
    --sans: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    --mono: "SF Mono", Menlo, Monaco, monospace;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  html, body { width: 1200px; height: 630px; overflow: hidden; }
  body {
    background: var(--bg);
    color: var(--ink);
    font-family: var(--sans);
    -webkit-font-smoothing: antialiased;
    display: grid;
    grid-template-columns: 1fr auto;
    align-items: center;
    gap: 56px;
    padding: 0 72px;
  }
  .left { max-width: 620px; }
  .brand { display: flex; align-items: center; gap: 14px; margin-bottom: 40px; }
  .brand svg { width: 46px; height: 46px; border-radius: 12px; }
  .brand .name { font-size: 26px; font-weight: 600; letter-spacing: -0.01em; }
  .brand .tag { font-family: var(--mono); font-size: 13px; color: var(--faint); letter-spacing: 0.04em; }
  h1 { font-size: 62px; line-height: 1.06; letter-spacing: -0.028em; font-weight: 600; }
  h1 em { font-style: normal; color: var(--live); }
  p { margin-top: 22px; font-size: 22px; line-height: 1.45; color: var(--muted); max-width: 30ch; }
  ul { list-style: none; margin-top: 38px; display: flex; flex-wrap: wrap; gap: 10px; }
  li {
    font-family: var(--mono); font-size: 14px; color: var(--muted);
    border: 1px solid var(--line); background: var(--surface);
    border-radius: 999px; padding: 7px 15px;
  }
  /* 面板截图是 377×814，卡片高 630——272pt 宽才能整张放下，不留底部裁切。 */
  .frame {
    width: 272px; border-radius: 20px; overflow: hidden;
    background: var(--surface); border: 1px solid var(--line);
    box-shadow: 0 2px 4px oklch(22% 0.012 260 / 0.05), 0 30px 60px -22px oklch(22% 0.05 260 / 0.32);
  }
  .frame img { display: block; width: 100%; height: auto; }
</style>
</head>
<body>
  <div class="left">
    <div class="brand">
      <svg viewBox="0 0 512 512" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <defs>
          <linearGradient id="g" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stop-color="#007AFF"/>
            <stop offset="100%" stop-color="#5AC8FA"/>
          </linearGradient>
        </defs>
        <rect width="512" height="512" rx="115" fill="url(#g)"/>
        <rect x="140" y="226" width="60" height="120" rx="10" fill="white" opacity="0.9"/>
        <rect x="226" y="166" width="60" height="180" rx="10" fill="white" opacity="0.9"/>
        <rect x="312" y="196" width="60" height="150" rx="10" fill="white" opacity="0.9"/>
      </svg>
      <div>
        <div class="name">Light Stats</div>
        <div class="tag">macOS menu bar instrument</div>
      </div>
    </div>
    <h1>Know if your Mac is <em>actually</em> struggling.</h1>
    <p>Live pressure signals folded into one health score, with optional AI, network, and Finder context.</p>
    <ul>
      <li>macOS 14+</li>
      <li>Apple Silicon</li>
      <li>MIT</li>
      <li>Free</li>
    </ul>
  </div>
  <div class="frame"><img src="file://$SHOT_ABS" alt=""></div>
</body>
</html>
HTML

"$CHROME" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1200,630 --screenshot="$PWD/$OUT" "file://$TMP/card.html" 2>/dev/null

[ -f "$OUT" ] || { echo "❌ 渲染失败：$OUT 未生成"; exit 1; }

# 分享卡片必须是 1200×630；尺寸不对说明渲染参数被改动过。
WIDTH="$(sips -g pixelWidth "$OUT" | awk '/pixelWidth/{print $2}')"
HEIGHT="$(sips -g pixelHeight "$OUT" | awk '/pixelHeight/{print $2}')"
if [ "$WIDTH" != "1200" ] || [ "$HEIGHT" != "630" ]; then
    echo "❌ 尺寸异常：${WIDTH}×${HEIGHT}，期望 1200×630"
    exit 1
fi

echo "✅ $OUT (${WIDTH}×${HEIGHT}, $(du -h "$OUT" | cut -f1))"

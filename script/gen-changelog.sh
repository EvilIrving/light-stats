#!/bin/bash
# =============================================================================
# gen-changelog.sh — 生成面向用户的 Release Changelog（输出到 stdout）
# =============================================================================
#
# 【这个脚本做什么】
#   生成面向终端用户的 GitHub Release 正文：
#     0. 若存在 docs/releases/<tag>.md（或 docs/releases/<version>.md），
#        直接使用该文件——正式版 / major 必须写这份，禁止用 docs: commit 当说明。
#     1. 否则取「上一个 tag → 当前 tag」之间的非 merge 提交。
#        可用环境变量 PREV_TAG 覆盖基线（如 PREV_TAG=v1.8.0）。
#     2. 过滤掉对用户无意义的类型：chore / ci / build / docs / test。
#     3. 若配置了 OpenAI 兼容 API → 调用 /chat/completions 改写成
#        精炼的「中英双语、按功能分组」release notes。
#     4. 没配 API / API 调用失败 → 自动降级为「按 feat/fix/perf 分类」的
#        纯脚本生成。降级保证发布流程永远不会因为 AI 不可用而中断。
#
# 【在 CI 里怎么跑】（已接入 .github/workflows/release.yml 的 Generate Changelog 步骤）
#   推送 v* tag 触发 Release 时自动执行，无需手动操作。等价于：
#       TAG=v1.2.3 ./script/gen-changelog.sh > CHANGELOG.md
#   生成的 CHANGELOG.md 只作为 workflow artifact 与 GitHub Release 正文，不回写仓库。
#
# 【本地怎么手动预览】
#   # 预览某个已存在 tag 的 changelog（走降级分类，不调 API）：
#       TAG=v1.2.3 ./script/gen-changelog.sh
#   # 预览「最新 tag → HEAD」尚未发布的内容：
#       ./script/gen-changelog.sh
#   # 本地试 AI 改写（需 jq + 一个 OpenAI 兼容端点）：
#       OPENAI_API_KEY=sk-xxx OPENAI_BASE_URL=https://your-host/v1 \
#       OPENAI_MODEL=gpt-4o-mini TAG=v1.2.3 ./script/gen-changelog.sh
#
# 【怎么启用 AI 改写】（可选，不配就用降级分类，效果也够用）
#   在 GitHub 仓库 Settings → Secrets and variables → Actions 里配置：
#     - Secret   OPENAI_API_KEY   你的 key（缺省 = 不启用 AI，走降级）
#     - Variable OPENAI_BASE_URL  端点，如 https://your-host/v1
#                                 缺省 https://api.openai.com/v1
#     - Variable OPENAI_MODEL     模型名，如 gpt-4o-mini（即缺省值）
#   兼容任何 OpenAI Chat Completions 风格的服务（官方 / 代理 / 自建）。
#
# 【环境变量一览】（全部可选）
#   TAG               目标 tag，缺省取当前 HEAD 上的 exact-match tag
#   OPENAI_API_KEY    配了才启用 AI 改写
#   OPENAI_BASE_URL   默认 https://api.openai.com/v1
#   OPENAI_MODEL      默认 gpt-4o-mini
#   GITHUB_REPOSITORY CI 自动注入，用于生成 Full Changelog 对比链接
#
# 【改排除规则 / 分组在哪改】
#   - 排除的提交类型：下方 EXCLUDE_RE。
#   - 降级时的分组逻辑：fallback_changelog() 里的 case 分支。
#   - AI 改写的提示词：ai_changelog() 里的 prompt 变量。
#
# 注意：本脚本兼容 macOS 自带 bash 3.2（CI runner 同款），勿用 mapfile 等 4.x 特性。
# =============================================================================
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-}"
TAG="${TAG:-$(git describe --tags --exact-match 2>/dev/null || echo HEAD)}"
# 允许显式指定对比基线（如跨多个预发布：PREV_TAG=v1.8.0 TAG=v1.9.0）
PREV_TAG="${PREV_TAG:-$(git describe --tags --abbrev=0 "${TAG}^" 2>/dev/null || echo "")}"

# 仓库根（CI checkout 与本地均可）
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# ---- 优先：手工撰写的面向用户 Release Notes ----
# 存在 docs/releases/<tag>.md 时直接使用（正式版/major 应写这份，勿把 docs: commit 当发布说明）。
# 面向用户的官网 Changelog 在 docs/index.html 的 Changelog 页签，发版时把新版本插到该页顶部。
curated_notes() {
    local f1="${ROOT}/docs/releases/${TAG}.md"
    local f2="${ROOT}/docs/releases/${TAG#v}.md"
    if [ -f "$f1" ]; then
        cat "$f1"
        return 0
    fi
    if [ -f "$f2" ]; then
        cat "$f2"
        return 0
    fi
    return 1
}

if curated_notes; then
    exit 0
fi

if [ -n "$PREV_TAG" ]; then
    RANGE="${PREV_TAG}..${TAG}"
else
    RANGE="$TAG"
fi

# 排除的提交类型 (不进用户 changelog)
EXCLUDE_RE='^(chore|ci|build|docs|test)(\(.*\))?(!)?:'

# 收集用户可见提交 (subject)，过滤排除类型 (bash 3.2 兼容，不用 mapfile)
COMMITS=()
while IFS= read -r line; do
    [ -n "$line" ] && COMMITS+=("$line")
done < <(
    if [ -n "$PREV_TAG" ]; then
        git log "$RANGE" --pretty=format:'%s' --no-merges
    else
        git log --pretty=format:'%s' --no-merges -30
    fi | grep -Ev "$EXCLUDE_RE" || true
)

compare_link() {
    if [ -n "$REPO" ] && [ -n "$PREV_TAG" ]; then
        echo ""
        echo "**Full Changelog**: https://github.com/${REPO}/compare/${PREV_TAG}...${TAG}"
    fi
}

# ---- 降级方案: 按 conventional-commit 类型分类 ----
fallback_changelog() {
    echo "## 更新内容 / What's Changed"
    echo ""
    local feats fixes perf other
    feats=""; fixes=""; perf=""; other=""
    for s in "${COMMITS[@]}"; do
        # 去掉 type(scope): 前缀，保留描述
        desc="$(echo "$s" | sed -E 's/^[a-z]+(\(.*\))?(!)?: *//')"
        case "$s" in
            feat*) feats+="- $desc"$'\n' ;;
            fix*)  fixes+="- $desc"$'\n' ;;
            perf*) perf+="- $desc"$'\n' ;;
            *)     other+="- $desc"$'\n' ;;
        esac
    done
    [ -n "$feats" ] && { echo "### ✨ 新功能 / Features";   echo ""; printf '%s\n' "$feats"; }
    [ -n "$fixes" ] && { echo "### 🐛 修复 / Fixes";        echo ""; printf '%s\n' "$fixes"; }
    [ -n "$perf"  ] && { echo "### ⚡ 优化 / Performance";  echo ""; printf '%s\n' "$perf"; }
    [ -n "$other" ] && { echo "### 🔧 其他 / Other";        echo ""; printf '%s\n' "$other"; }
    compare_link
}

# ---- AI 方案: OpenAI 兼容 /chat/completions ----
ai_changelog() {
    local base="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    local model="${OPENAI_MODEL:-gpt-4o-mini}"
    local commit_text prompt payload resp content

    commit_text="$(printf '%s\n' "${COMMITS[@]}")"

    prompt="你是发布说明撰写者。下面是 Light Stats (macOS 菜单栏系统监控 app) 自上个版本以来的 git 提交。\
请改写成面向终端用户的精炼 Release Notes：中英双语，按「新功能 / 修复 / 优化 / 其他」分组，\
每条一句话、去掉技术术语和 commit 前缀，省略无用户价值的条目。直接输出 Markdown，不要额外解释。\
\n\n提交列表:\n${commit_text}"

    # 用 jq 安全构造 JSON
    payload="$(jq -n --arg model "$model" --arg content "$prompt" '{
        model: $model,
        temperature: 0.3,
        messages: [{role: "user", content: $content}]
    }')"

    resp="$(curl -sS --max-time 60 -X POST "${base%/}/chat/completions" \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$payload")" || return 1

    content="$(echo "$resp" | jq -r '.choices[0].message.content // empty')"
    [ -z "$content" ] && return 1

    echo "$content"
    compare_link
}

# ---- 主流程 ----
if [ "${#COMMITS[@]}" -eq 0 ]; then
    echo "## 更新内容 / What's Changed"
    echo ""
    echo "- 维护性更新 / Maintenance release"
    compare_link
    exit 0
fi

if [ -n "${OPENAI_API_KEY:-}" ] && command -v jq >/dev/null 2>&1; then
    if ai_changelog; then
        exit 0
    fi
    echo "::warning::AI changelog 生成失败，降级为分类脚本。" >&2
fi

fallback_changelog

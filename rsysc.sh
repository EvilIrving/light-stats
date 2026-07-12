#!/usr/bin/env bash

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 源 skills 目录
SRC_SKILLS="$SCRIPT_DIR/.agents/skills"

# 目标目录数组
TARGETS=(
  "$SCRIPT_DIR/.claude/skills"
  "$SCRIPT_DIR/.codex/skills"
  "$SCRIPT_DIR/.cursor/skills"
  "$SCRIPT_DIR/.pi/skills"
  "$SCRIPT_DIR/.grok/skills"
)

# 遍历每个目标目录
for target in "${TARGETS[@]}"; do
  echo "同步到: $target"

  # 确保目标目录存在
  mkdir -p "$target"

  # 遍历源目录下的每个 skill
  for skill_path in "$SRC_SKILLS"/*; do
    [ -e "$skill_path" ] || continue  # 跳过空目录
    [ -d "$skill_path" ] || continue  # 跳过非目录项

    skill_name=$(basename "$skill_path")
    target_skill="$target/$skill_name"

    # 如果目标已存在，跳过
    if [ -e "$target_skill" ] || [ -L "$target_skill" ]; then
      continue
    fi

    # 直接软链接整个 skill 目录
    ln -s "$skill_path" "$target_skill"
    echo "  已链接: $skill_name"
  done
done

echo "同步完成"

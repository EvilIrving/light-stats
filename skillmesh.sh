#!/usr/bin/env bash
# =============================================================================
# skillmesh 使用说明
# =============================================================================
#
# skillmesh 用来管理多个 AI Agent 的 Skills。它把 .agents/skills 当作统一源库，
# 再将其中的 Skill 以软链形式同步到 Claude、Codex、Cursor、Pi 和 Grok。
# 除了全局目录，也可以在单个项目中维护一套项目专用的 Skills。
#
# 本脚本不负责从市场、Git 仓库或压缩包中寻找和下载 Skill；这些内容拿到本地后，
# 可用 import 加入源库，或用 adopt 收纳某个 Agent 已经拥有的 Skill。
# 完整的运行时帮助可通过 ./skillmesh --help 查看。
#
# 目录约定
# --------
#
# 全局模式是默认模式。它使用下面这些目录：
#
#   源库
#     ${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}/.agents/skills/<skill>/SKILL.md
#
#   Agent 目标目录
#     ${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}/.claude/skills/<skill>
#     ${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}/.codex/skills/<skill>
#     ${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}/.cursor/skills/<skill>
#     ${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}/.pi/skills/<skill>
#     ${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}/.grok/skills/<skill>
#
# SKILLMESH_HOME 可用来替代 $HOME，例如管理另一套用户目录或编写测试。
# 旧的 RSYSC_HOME 仍然兼容；两者同时存在时 SKILLMESH_HOME 优先。
#
# 项目模式通过 --scope project 启用。项目根目录由 --project DIR 指定；如果没有
# 指定，脚本会优先寻找当前目录所在的 Git 根目录，找不到 Git 仓库时使用当前目录。
# 项目目录的结构与全局目录一致：
#
#   <project>/.agents/skills/<skill>/SKILL.md
#   <project>/.claude/skills/<skill>
#   <project>/.codex/skills/<skill>
#   <project>/.cursor/skills/<skill>
#   <project>/.pi/skills/<skill>
#   <project>/.grok/skills/<skill>
#
# 项目命令加上 --include-global 后，项目会额外使用全局源库。项目内存在同名 Skill
# 时，项目版本优先，因此可以用它覆盖某个全局 Skill。
#
# 一个可管理的 Skill 是源库中的一级目录，且其中包含 SKILL.md。源库里的条目可以
# 是真实目录，也可以是指向外部 Skill 目录的软链。
#
# 基本命令
# --------
#
# sync [skill ...]
#   将源库中的 Skill 同步到目标 Agent。没有指定 Skill 时同步全部；指定名称时只
#   同步这些名称。同步会创建缺失的软链、更新已经由本脚本管理的错误软链，并默认
#   清理当前源库中已经不存在的受管断链。
#
# status [skill ...]
#   查看每个 Agent 的状态。输出包含已链接、缺失、冲突、失效软链以及脚本没有管理
#   的外部项目。该命令不会修改文件。
#
# clean [skill ...]
#   清理指向当前源库、但源 Skill 已被删除的软链。加 --orphaned 时，也会识别并
#   清理指向不存在 .agents/skills 路径的其他断链。
#
# doctor [skill ...]
#   检查源 Skill 是否包含 SKILL.md，并检查目标目录中缺失的链接、错误链接、冲突
#   和断链。适合用来定位同步异常。
#
# list
#   列出当前作用域里可用的 Skill。项目使用 --include-global 时，继承的全局 Skill
#   会在输出中标记出来。
#
# init
#   创建当前作用域的 .agents/skills 和选定 Agent 的 skills 目录。不会创建任何
#   Skill，也不会改动已有内容。
#
# import PATH
#   将 PATH 指向的本地 Skill 放进当前源库。默认在源库中创建指向 PATH 的软链；
#   使用 --copy 可以复制完整目录。PATH 必须是含有 SKILL.md 的目录。
#
# adopt --from AGENT
#   扫描指定 Agent 现有的 skills 目录，将尚未由当前源库管理、并且带有 SKILL.md
#   的 Skill 收纳到源库。它适合处理先前手工安装或由其他工具安装的 Skill。
#
# enable SKILL [...] / disable SKILL [...]
#   enable 是 sync 的简写，用于只向指定 Agent 启用几个 Skill。disable 是 remove
#   的简写，只移除目标目录中的受管软链，源库里的 Skill 会保留。
#
# 常用示例
# --------
#
# 查看当前全局库，以及预览一次全局同步：
#   ./skillmesh status
#   ./skillmesh sync --dry-run
#
# 同步所有全局 Skill：
#   ./skillmesh sync
#
# 只同步 Claude 与 Pi：
#   ./skillmesh sync --target claude,pi
#
# 只启用一个 Skill：
#   ./skillmesh enable browser-extension-release --target claude --target pi
#
# 管理项目中的本地 Skill：
#   ./skillmesh status --scope project --project ~/code/my-app
#   ./skillmesh sync --scope project --project ~/code/my-app
#
# 让项目同时使用全局库；项目中同名目录会覆盖全局版本：
#   ./skillmesh sync --scope project --project ~/code/my-app --include-global
#
# 将一个本地目录加入全局源库，再分发给 Claude 和 Pi：
#   ./skillmesh import ~/Downloads/my-skill --sync --target claude,pi
#
# 复制而不是软链导入，并指定它在源库中的名称：
#   ./skillmesh import ~/Downloads/my-skill --copy --name my-skill-copy
#
# 收纳 Claude 已经有的 Skill；收纳后可再运行 sync 分发给其他 Agent：
#   ./skillmesh adopt --from claude
#
# 清理源已经删除后的残留软链：
#   ./skillmesh clean --dry-run
#   ./skillmesh clean
#
# 参数说明
# --------
#
# --scope global|project|all
#   选择全局、项目，或依次操作两者。默认是 global。
#
# --project DIR
#   指定项目根目录；通常与 --scope project 一起使用。
#
# --target AGENT[,AGENT...]
#   仅操作指定 Agent。支持 claude、codex、cursor、pi、grok，可重复传入，也可用
#   逗号一次传入多个，例如 --target claude,pi。
#
# --include-global
#   项目模式下把全局源库加入可用列表，项目内同名 Skill 仍然优先。
#
# --dry-run 或 -n
#   只打印将发生的新增、更新、删除和冲突，不实际修改文件。
#
# --no-prune
#   sync 时保留源已不存在的受管软链，不执行默认的断链清理。
#
# --orphaned
#   clean 时扩大检查范围，处理其他已经失效、但同样指向 .agents/skills 的软链。
#
# --force 或 -f
#   当目标存在指向其他位置的软链时，用新的受管软链替换它。真实文件和目录不会被
#   --force 覆盖。
#
# --link / --copy
#   import 和 adopt 的收纳方式。--link 是默认方式，源库保存指向原目录的软链；
#   --copy 则在源库中保留一份独立副本。
#
# --sync
#   import 或 adopt 完成后，立即把本次新加入源库的 Skill 同步到选定 Agent。
#
# --name NAME
#   import 时指定源库中的 Skill 名称；不传时使用导入目录的名称。
#
# --from AGENT
#   adopt 时的来源 Agent，例如 --from claude。
#
# --verbose 或 -v
#   在 status、doctor、sync 等命令中额外显示已正确处理的条目。
#
# 使用中的一些行为
# ----------------
#
# sync 和 clean 删除的只是软链；已有的真实文件、真实目录或外部软链会保留，并作为
# 冲突或外部项显示。--force 可以替换冲突的软链，但不会覆盖真实文件或目录。
# import 与 adopt 不会覆盖源库中已有同名 Skill；遇到重名条目会跳过并保留现状。
# 命令成功且没有报告问题时返回 0；遇到冲突、缺失、校验错误或操作失败时返回 1；
# 参数错误返回 2。
# =============================================================================
# skillmesh: 轻量的 Agent Skill 管理器。
# 可用 SKILLMESH_HOME 覆盖全局根目录；RSYSC_HOME 仍作为兼容别名保留。

set -o pipefail

VERSION="2.0.0"
SCRIPT_NAME="$(basename "$0")"
GLOBAL_ROOT="${SKILLMESH_HOME:-${RSYSC_HOME:-$HOME}}"
DEFAULT_AGENTS=(claude codex cursor pi grok)

COMMAND="sync"
SCOPE="global"
PROJECT_ARGUMENT=""
TARGET_FILTER=()
SKILL_FILTER=()
DRY_RUN=0
FORCE=0
PRUNE=1
INCLUDE_GLOBAL=0
ORPHANED=0
VERBOSE=0
IMPORT_NAME=""
IMPORT_MODE="link"
IMPORT_MODE_EXPLICIT=0
SYNC_AFTER_IMPORT=0
ADOPT_AGENT=""
REQUIRE_SKILL_FILTER=0

# 由 setup_scope 填充。
SCOPE_ROOT=""
PRIMARY_SOURCE=""
SECONDARY_SOURCE=""
MANAGED_SOURCES=()
EFFECTIVE_SKILLS=()
ACTIVE_AGENTS=()

CREATED=0
UPDATED=0
REMOVED=0
UNCHANGED=0
CONFLICTS=0
ISSUES=0
IMPORTED=0

usage() {
  cat <<EOF
用法：
  $SCRIPT_NAME [命令] [选项] [skill ...]

命令：
  sync       同步源目录到目标 Agent 目录；默认命令，会清理当前作用域的失效软链
  status     查看每个 Agent 目录的同步状态、冲突和断链
  clean      只清理由当前作用域管理且源已不存在的软链
  doctor     检查 SKILL.md、断链、冲突和缺失的目标链接
  list       列出当前作用域中有效的 skill
  init       创建源目录与选定的目标目录，不创建任何 skill
  import     将一个本地 skill 目录加入当前源库（默认创建软链）
  adopt      从某个 Agent 目录收纳已有 skill 到当前源库
  remove     从选定目标中移除指定 skill 的受管软链，不删除源 skill
  enable     sync 的别名，要求至少指定一个 skill
  disable    remove 的别名
  help       显示本帮助

作用域：
  --scope global     全局：$HOME/.agents/skills（默认）
  --scope project    项目：<项目>/.agents/skills
  --scope all        依次处理全局与项目作用域
  --project DIR      指定项目根目录；未指定时优先使用 Git 根目录，否则当前目录
  --include-global   项目作用域额外继承全局 skill；同名项目 skill 优先

选项：
  --target NAME      仅处理一个 Agent：claude、codex、cursor、pi、grok；可重复或使用逗号分隔
  --dry-run, -n      只显示将要发生的变更，不修改文件
  --no-prune         sync 时不清理当前作用域的失效软链
  --orphaned         clean 时额外清理所有指向已失效 .agents/skills 的断链
  --name NAME        import 时指定加入源库后的 skill 名称
  --from AGENT       adopt 时指定来源 Agent（claude、codex、cursor、pi、grok）
  --link             import/adopt 时在源库创建软链（默认）
  --copy             import/adopt 时复制目录到源库，而非创建软链
  --sync             import/adopt 后把本次加入的 skill 同步到选定 Agent
  --force, -f        允许替换冲突的软链；永远不会覆盖真实文件或目录
  --verbose, -v      显示已正确链接的详细信息
  --help, -h         显示本帮助

示例：
  $SCRIPT_NAME sync
  $SCRIPT_NAME status --scope global
  $SCRIPT_NAME sync --scope project --project ~/code/my-app
  $SCRIPT_NAME sync --scope project --include-global --dry-run
  $SCRIPT_NAME clean --scope global --orphaned
  $SCRIPT_NAME import ~/Downloads/my-skill --sync --target claude,pi
  $SCRIPT_NAME adopt --scope project --project ~/code/my-app --from claude
  $SCRIPT_NAME enable browser-extension-release --target claude --target pi
  $SCRIPT_NAME disable browser-extension-release --scope project --project ~/code/my-app

安全规则：
  - 自动删除只会删除软链，绝不会删除真实文件或目录。
  - 遇到同名真实目录/文件或指向其他位置的软链时默认报冲突并保留。
  - --force 只会替换软链，仍不会覆盖真实文件或目录。
  - import/adopt 不会覆盖已有源 skill；重名项会保留并报告。
EOF
}

info() {
  printf '%s\n' "$*"
}

warn() {
  printf '警告：%s\n' "$*" >&2
  ISSUES=$((ISSUES + 1))
}

error() {
  printf '错误：%s\n' "$*" >&2
  ISSUES=$((ISSUES + 1))
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 2
}

absolute_existing_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# 仅进行词法规范化，因此即使目标是断链也能判断它原本指向哪里。
normalize_path() {
  local path="$1"
  local base="${2:-}"
  local combined part old_ifs result
  local -a pieces stack

  if [[ "$path" == /* ]]; then
    combined="$path"
  else
    [ -n "$base" ] || return 1
    combined="$base/$path"
  fi

  old_ifs="$IFS"
  IFS='/'
  read -r -a pieces <<< "$combined"
  IFS="$old_ifs"

  stack=()
  for part in "${pieces[@]}"; do
    case "$part" in
      ''|'.') ;;
      '..')
        if [ "${#stack[@]}" -gt 0 ]; then
          unset "stack[$((${#stack[@]} - 1))]"
        fi
        ;;
      *) stack+=("$part") ;;
    esac
  done

  result=""
  for part in "${stack[@]}"; do
    result="$result/$part"
  done
  printf '%s\n' "${result:-/}"
}

link_destination() {
  local link="$1"
  local raw parent

  raw="$(readlink "$link")" || return 1
  parent="$(absolute_existing_dir "$(dirname "$link")")" || return 1
  normalize_path "$raw" "$parent"
}

contains_value() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    [ "$value" = "$needle" ] && return 0
  done
  return 1
}

append_unique() {
  local value="$1"
  shift
  contains_value "$value" "$@" && return 0
  return 1
}

valid_skill_name() {
  [ -n "$1" ] && [[ "$1" != */* ]] && [ "$1" != "." ] && [ "$1" != ".." ]
}

agent_dir_name() {
  case "$1" in
    claude) printf '.claude\n' ;;
    codex) printf '.codex\n' ;;
    cursor) printf '.cursor\n' ;;
    pi) printf '.pi\n' ;;
    grok) printf '.grok\n' ;;
    *) return 1 ;;
  esac
}

add_target_value() {
  local value="$1"
  local item old_ifs
  local -a values

  old_ifs="$IFS"
  IFS=','
  read -r -a values <<< "$value"
  IFS="$old_ifs"

  for item in "${values[@]}"; do
    case "$item" in
      all)
        TARGET_FILTER=(all)
        return 0
        ;;
      claude|codex|cursor|pi|grok)
        if ! contains_value "$item" "${TARGET_FILTER[@]}"; then
          TARGET_FILTER+=("$item")
        fi
        ;;
      *) die "未知 Agent：${item}（可用：claude、codex、cursor、pi、grok）" ;;
    esac
  done
}

build_active_agents() {
  local agent
  ACTIVE_AGENTS=()

  if [ "${#TARGET_FILTER[@]}" -eq 0 ] || contains_value all "${TARGET_FILTER[@]}"; then
    ACTIVE_AGENTS=("${DEFAULT_AGENTS[@]}")
    return 0
  fi

  for agent in "${TARGET_FILTER[@]}"; do
    if ! contains_value "$agent" "${ACTIVE_AGENTS[@]}"; then
      ACTIVE_AGENTS+=("$agent")
    fi
  done
}

resolve_project_root() {
  local root

  if [ -n "$PROJECT_ARGUMENT" ]; then
    root="$(absolute_existing_dir "$PROJECT_ARGUMENT")" || return 1
  else
    root="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$root" ]; then
      root="$(absolute_existing_dir "$root")" || return 1
    else
      root="$(absolute_existing_dir "$PWD")" || return 1
    fi
  fi

  printf '%s\n' "$root"
}

setup_scope() {
  local requested_scope="$1"
  local global_root project_root

  SCOPE_ROOT=""
  PRIMARY_SOURCE=""
  SECONDARY_SOURCE=""
  MANAGED_SOURCES=()

  case "$requested_scope" in
    global)
      global_root="$(absolute_existing_dir "$GLOBAL_ROOT")" || {
        error "全局根目录不存在：$GLOBAL_ROOT"
        return 1
      }
      SCOPE_ROOT="$global_root"
      PRIMARY_SOURCE="$(normalize_path "$global_root/.agents/skills" /)"
      MANAGED_SOURCES=("$PRIMARY_SOURCE")
      ;;
    project)
      project_root="$(resolve_project_root)" || {
        error "项目目录不存在：${PROJECT_ARGUMENT:-$PWD}"
        return 1
      }
      SCOPE_ROOT="$project_root"
      PRIMARY_SOURCE="$(normalize_path "$project_root/.agents/skills" /)"
      MANAGED_SOURCES=("$PRIMARY_SOURCE")

      if [ "$INCLUDE_GLOBAL" -eq 1 ]; then
        global_root="$(absolute_existing_dir "$GLOBAL_ROOT")" || {
          error "全局根目录不存在：$GLOBAL_ROOT"
          return 1
        }
        SECONDARY_SOURCE="$(normalize_path "$global_root/.agents/skills" /)"
        if ! contains_value "$SECONDARY_SOURCE" "${MANAGED_SOURCES[@]}"; then
          MANAGED_SOURCES+=("$SECONDARY_SOURCE")
        fi
      fi
      ;;
    *)
      error "未知作用域：$requested_scope"
      return 1
      ;;
  esac

  build_active_agents
}

collect_dir_skills() {
  local source="$1"
  local entry
  COLLECTED_SKILLS=()

  [ -d "$source" ] || return 0
  shopt -s nullglob
  for entry in "$source"/*; do
    [ -d "$entry" ] || continue
    COLLECTED_SKILLS+=("$(basename "$entry")")
  done
  shopt -u nullglob
}

source_for_skill() {
  local skill="$1"

  if [ -d "$PRIMARY_SOURCE/$skill" ]; then
    printf '%s\n' "$PRIMARY_SOURCE/$skill"
    return 0
  fi
  if [ -n "$SECONDARY_SOURCE" ] && [ -d "$SECONDARY_SOURCE/$skill" ]; then
    printf '%s\n' "$SECONDARY_SOURCE/$skill"
    return 0
  fi
  return 1
}

build_effective_skills() {
  local skill
  local -a primary_skills secondary_skills selected

  EFFECTIVE_SKILLS=()
  collect_dir_skills "$PRIMARY_SOURCE"
  primary_skills=("${COLLECTED_SKILLS[@]}")
  for skill in "${primary_skills[@]}"; do
    EFFECTIVE_SKILLS+=("$skill")
  done

  if [ -n "$SECONDARY_SOURCE" ]; then
    collect_dir_skills "$SECONDARY_SOURCE"
    secondary_skills=("${COLLECTED_SKILLS[@]}")
    for skill in "${secondary_skills[@]}"; do
      if ! contains_value "$skill" "${EFFECTIVE_SKILLS[@]}"; then
        EFFECTIVE_SKILLS+=("$skill")
      fi
    done
  fi

  if [ "${#SKILL_FILTER[@]}" -gt 0 ]; then
    selected=()
    for skill in "${SKILL_FILTER[@]}"; do
      if ! valid_skill_name "$skill"; then
        error "非法 skill 名称：$skill"
        continue
      fi
      if source_for_skill "$skill" >/dev/null; then
        if ! contains_value "$skill" "${selected[@]}"; then
          selected+=("$skill")
        fi
      else
        error "源目录中不存在 skill：$skill"
      fi
    done
    EFFECTIVE_SKILLS=("${selected[@]}")
  fi
}

source_available() {
  [ -d "$PRIMARY_SOURCE" ] || { [ -n "$SECONDARY_SOURCE" ] && [ -d "$SECONDARY_SOURCE" ]; }
}

target_directory() {
  local agent="$1"
  local agent_dir
  agent_dir="$(agent_dir_name "$agent")" || return 1
  printf '%s/%s/skills\n' "$SCOPE_ROOT" "$agent_dir"
}

link_matches_path() {
  local target="$1"
  local expected="$2"
  local destination actual_target actual_expected

  if [ -L "$target" ]; then
    destination="$(link_destination "$target")" || return 1
    [ "$destination" = "$expected" ] && return 0
  fi

  # 当源库中的 skill 本身也是软链时，目标直接指向其真实目录同样视为正确。
  [ -d "$target" ] && [ -d "$expected" ] || return 1
  actual_target="$(absolute_existing_dir "$target")" || return 1
  actual_expected="$(absolute_existing_dir "$expected")" || return 1
  [ "$actual_target" = "$actual_expected" ]
}

link_is_managed() {
  local link="$1"
  local skill destination source

  [ -L "$link" ] || return 1
  skill="$(basename "$link")"
  destination="$(link_destination "$link")" || return 1
  for source in "${MANAGED_SOURCES[@]}"; do
    [ "$destination" = "$source/$skill" ] && return 0
  done
  return 1
}

link_is_stale_managed() {
  local link="$1"
  local destination

  link_is_managed "$link" || return 1
  destination="$(link_destination "$link")" || return 1
  [ ! -d "$destination" ]
}

link_is_orphaned_skill_link() {
  local link="$1"
  local destination

  [ -L "$link" ] || return 1
  destination="$(link_destination "$link")" || return 1
  case "$destination" in
    */.agents/skills/*) [ ! -d "$destination" ] ;;
    *) return 1 ;;
  esac
}

ensure_directory() {
  local directory="$1"

  if [ -d "$directory" ]; then
    return 0
  fi
  if [ -e "$directory" ]; then
    error "目标路径不是目录：$directory"
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    info "  [dry-run] 创建目录：$directory"
    return 0
  fi
  if ! mkdir -p "$directory"; then
    error "无法创建目录：$directory"
    return 1
  fi
  info "  已创建目录：$directory"
}

create_link() {
  local source="$1"
  local target="$2"

  if [ "$DRY_RUN" -eq 1 ]; then
    info "  [dry-run] 链接：$(basename "$target") -> $source"
  elif ln -s "$source" "$target"; then
    info "  已链接：$(basename "$target")"
  else
    error "无法创建软链：$target"
    return 1
  fi
  CREATED=$((CREATED + 1))
}

replace_link() {
  local source="$1"
  local target="$2"
  local temp="${target}.skillmesh-tmp-$$"

  [ -L "$target" ] || {
    error "拒绝替换非软链：$target"
    return 1
  }

  if [ "$DRY_RUN" -eq 1 ]; then
    info "  [dry-run] 更新软链：$(basename "$target") -> $source"
  else
    if ! ln -s "$source" "$temp"; then
      error "无法创建临时软链：$temp"
      return 1
    fi
    if ! mv -f "$temp" "$target"; then
      rm -f "$temp"
      error "无法更新软链：$target"
      return 1
    fi
    info "  已更新软链：$(basename "$target")"
  fi
  UPDATED=$((UPDATED + 1))
}

remove_link() {
  local target="$1"
  local reason="$2"

  [ -L "$target" ] || {
    error "拒绝删除非软链：$target"
    return 1
  }

  if [ "$DRY_RUN" -eq 1 ]; then
    info "  [dry-run] 删除软链：$(basename "$target")（${reason}）"
  elif rm "$target"; then
    info "  已删除软链：$(basename "$target")（${reason}）"
  else
    error "无法删除软链：$target"
    return 1
  fi
  REMOVED=$((REMOVED + 1))
}

cleanup_target() {
  local target="$1"
  local entry skill

  [ -d "$target" ] || return 0
  shopt -s nullglob
  for entry in "$target"/*; do
    [ -L "$entry" ] || continue
    skill="$(basename "$entry")"
    if [ "${#SKILL_FILTER[@]}" -gt 0 ] && ! contains_value "$skill" "${SKILL_FILTER[@]}"; then
      continue
    fi

    if link_is_stale_managed "$entry"; then
      remove_link "$entry" "源 skill 已不存在"
    elif [ "$ORPHANED" -eq 1 ] && link_is_orphaned_skill_link "$entry"; then
      remove_link "$entry" "失效的外部 skill 软链"
    fi
  done
  shopt -u nullglob
}

sync_target() {
  local target="$1"
  local skill source target_skill destination

  ensure_directory "$target" || return 1

  for skill in "${EFFECTIVE_SKILLS[@]}"; do
    source="$(source_for_skill "$skill")" || {
      error "无法定位 skill 源：$skill"
      continue
    }
    target_skill="$target/$skill"

    if link_matches_path "$target_skill" "$source"; then
      UNCHANGED=$((UNCHANGED + 1))
      [ "$VERBOSE" -eq 1 ] && info "  已同步：$skill"
    elif [ -L "$target_skill" ]; then
      if link_is_managed "$target_skill"; then
        replace_link "$source" "$target_skill"
      elif [ "$FORCE" -eq 1 ]; then
        replace_link "$source" "$target_skill"
      else
        destination="$(link_destination "$target_skill" 2>/dev/null || printf '未知目标')"
        warn "冲突，保留外部软链：${target_skill} -> ${destination}（加 --force 可替换）"
        CONFLICTS=$((CONFLICTS + 1))
      fi
    elif [ -e "$target_skill" ]; then
      warn "冲突，保留真实文件或目录：$target_skill"
      CONFLICTS=$((CONFLICTS + 1))
    else
      create_link "$source" "$target_skill"
    fi
  done

  if [ "$PRUNE" -eq 1 ]; then
    cleanup_target "$target"
  fi
}

run_sync_scope() {
  local scope="$1"
  local agent target

  setup_scope "$scope" || return 1
  if ! source_available; then
    error "源 skills 目录不存在：$PRIMARY_SOURCE"
    return 1
  fi

  build_effective_skills
  if [ "${#EFFECTIVE_SKILLS[@]}" -eq 0 ]; then
    warn "没有可同步的 skill：$PRIMARY_SOURCE"
  fi

  info "同步 $scope 作用域：$PRIMARY_SOURCE"
  [ -n "$SECONDARY_SOURCE" ] && info "  继承全局源：$SECONDARY_SOURCE"
  for agent in "${ACTIVE_AGENTS[@]}"; do
    target="$(target_directory "$agent")"
    info "- $agent: $target"
    sync_target "$target"
  done
}

status_target() {
  local target="$1"
  local agent="$2"
  local skill source target_skill destination entry
  local linked=0 missing=0 conflicts=0 stale=0 external=0

  if [ ! -d "$target" ]; then
    info "- ${agent}: 目标目录不存在（${target}）"
    return 0
  fi

  for skill in "${EFFECTIVE_SKILLS[@]}"; do
    source="$(source_for_skill "$skill")" || continue
    target_skill="$target/$skill"
    if link_matches_path "$target_skill" "$source"; then
      linked=$((linked + 1))
      [ "$VERBOSE" -eq 1 ] && info "  已链接：$skill"
    elif [ -L "$target_skill" ]; then
      destination="$(link_destination "$target_skill" 2>/dev/null || printf '未知目标')"
      info "  冲突：$skill -> $destination"
      conflicts=$((conflicts + 1))
    elif [ -e "$target_skill" ]; then
      info "  冲突：$skill 被真实文件或目录占用"
      conflicts=$((conflicts + 1))
    else
      info "  缺失：$skill"
      missing=$((missing + 1))
    fi
  done

  shopt -s nullglob
  for entry in "$target"/*; do
    skill="$(basename "$entry")"
    contains_value "$skill" "${EFFECTIVE_SKILLS[@]}" && continue
    if link_is_stale_managed "$entry"; then
      info "  失效受管软链：$skill"
      stale=$((stale + 1))
    elif [ -L "$entry" ] && [ ! -e "$entry" ]; then
      info "  失效外部软链：$skill"
      external=$((external + 1))
    elif [ -L "$entry" ]; then
      [ "$VERBOSE" -eq 1 ] && info "  外部软链：$skill"
      external=$((external + 1))
    elif [ -e "$entry" ]; then
      [ "$VERBOSE" -eq 1 ] && info "  外部文件/目录：$skill"
      external=$((external + 1))
    fi
  done
  shopt -u nullglob

  info "- ${agent}: 已链接 ${linked}，缺失 ${missing}，冲突 ${conflicts}，失效 ${stale}，外部项 ${external}"
}

run_status_scope() {
  local scope="$1"
  local agent target

  setup_scope "$scope" || return 1
  build_effective_skills
  info "状态 $scope 作用域：$PRIMARY_SOURCE"
  [ -n "$SECONDARY_SOURCE" ] && info "  继承全局源：$SECONDARY_SOURCE"
  if ! source_available; then
    info "  源目录不存在；仍检查可识别的失效受管软链。"
  fi
  for agent in "${ACTIVE_AGENTS[@]}"; do
    target="$(target_directory "$agent")"
    status_target "$target" "$agent"
  done
}

run_clean_scope() {
  local scope="$1"
  local agent target

  setup_scope "$scope" || return 1
  info "清理 $scope 作用域：$PRIMARY_SOURCE"
  [ "$ORPHANED" -eq 1 ] && info "  同时清理所有失效 .agents/skills 软链。"
  for agent in "${ACTIVE_AGENTS[@]}"; do
    target="$(target_directory "$agent")"
    [ -d "$target" ] || {
      [ "$VERBOSE" -eq 1 ] && info "- $agent: 目标目录不存在，跳过"
      continue
    }
    info "- $agent: $target"
    cleanup_target "$target"
  done
}

run_list_scope() {
  local scope="$1"
  local skill source

  setup_scope "$scope" || return 1
  build_effective_skills
  info "Skill 列表（${scope}）："
  if [ "${#EFFECTIVE_SKILLS[@]}" -eq 0 ]; then
    info "  （无；源目录：${PRIMARY_SOURCE}）"
    return 0
  fi
  for skill in "${EFFECTIVE_SKILLS[@]}"; do
    source="$(source_for_skill "$skill")" || continue
    if [ "$source" = "$PRIMARY_SOURCE/$skill" ]; then
      info "  $skill"
    else
      info "  ${skill}（继承自全局）"
    fi
  done
}

run_init_scope() {
  local scope="$1"
  local agent target

  setup_scope "$scope" || return 1
  info "初始化 $scope 作用域：$SCOPE_ROOT"
  ensure_directory "$PRIMARY_SOURCE" || return 1
  for agent in "${ACTIVE_AGENTS[@]}"; do
    target="$(target_directory "$agent")"
    ensure_directory "$target" || true
  done
}

import_directory_into_library() {
  local external_source="$1"
  local skill="$2"
  local destination

  destination="$PRIMARY_SOURCE/$skill"
  if [ -e "$destination" ] || [ -L "$destination" ]; then
    info "  源库已有 ${skill}，跳过"
    return 0
  fi

  case "$external_source" in
    "$PRIMARY_SOURCE"|"$PRIMARY_SOURCE"/*)
      error "拒绝导入源库内部目录：${external_source}"
      return 1
      ;;
  esac

  ensure_directory "$PRIMARY_SOURCE" || return 1
  if [ "$DRY_RUN" -eq 1 ]; then
    info "  [dry-run] ${IMPORT_MODE} 导入：${skill} <- ${external_source}"
  elif [ "$IMPORT_MODE" = "link" ]; then
    if ! ln -s "$external_source" "$destination"; then
      error "无法创建源库软链：${destination}"
      return 1
    fi
    info "  已软链导入：${skill}"
  elif cp -R -L "$external_source" "$destination"; then
    info "  已复制导入：${skill}"
  else
    error "无法复制到源库：${destination}"
    return 1
  fi

  IMPORTED=$((IMPORTED + 1))
}

run_import_scope() {
  local scope="$1"
  local external_input external_source skill

  if [ "${#SKILL_FILTER[@]}" -ne 1 ]; then
    error "import 需要且只能提供一个本地 skill 目录"
    return 1
  fi

  setup_scope "$scope" || return 1
  external_input="${SKILL_FILTER[0]}"
  external_source="$(absolute_existing_dir "$external_input")" || {
    error "要导入的 skill 目录不存在：${external_input}"
    return 1
  }
  if [ ! -f "$external_source/SKILL.md" ]; then
    error "要导入的目录缺少 SKILL.md：${external_source}"
    return 1
  fi

  skill="${IMPORT_NAME:-$(basename "$external_source")}" 
  if ! valid_skill_name "$skill"; then
    error "非法 skill 名称：${skill}"
    return 1
  fi

  info "导入到 ${scope} 源库：${PRIMARY_SOURCE}"
  import_directory_into_library "$external_source" "$skill" || return 1

  if [ "$SYNC_AFTER_IMPORT" -eq 1 ]; then
    SKILL_FILTER=("$skill")
    run_sync_scope "$scope"
  fi
}

run_adopt_scope() {
  local scope="$1"
  local source_target entry skill external_source destination existed
  local -a adopted_skills

  if [ -z "$ADOPT_AGENT" ]; then
    error "adopt 需要 --from AGENT"
    return 1
  fi
  agent_dir_name "$ADOPT_AGENT" >/dev/null || {
    error "未知来源 Agent：${ADOPT_AGENT}"
    return 1
  }

  setup_scope "$scope" || return 1
  source_target="$(target_directory "$ADOPT_AGENT")"
  if [ ! -d "$source_target" ]; then
    error "来源 Agent 目录不存在：${source_target}"
    return 1
  fi
  ensure_directory "$PRIMARY_SOURCE" || return 1

  adopted_skills=()
  info "从 ${ADOPT_AGENT} 收纳 skill 到 ${scope} 源库"
  shopt -s nullglob
  for entry in "$source_target"/*; do
    skill="$(basename "$entry")"
    if [ "${#SKILL_FILTER[@]}" -gt 0 ] && ! contains_value "$skill" "${SKILL_FILTER[@]}"; then
      continue
    fi
    if [ -L "$entry" ] && [ ! -e "$entry" ]; then
      warn "跳过失效软链：${ADOPT_AGENT}/${skill}"
      continue
    fi
    [ -d "$entry" ] || continue
    if [ ! -f "$entry/SKILL.md" ]; then
      [ "$VERBOSE" -eq 1 ] && info "  跳过无 SKILL.md 的目录：${skill}"
      continue
    fi
    if link_is_managed "$entry"; then
      [ "$VERBOSE" -eq 1 ] && info "  已受管：${skill}"
      continue
    fi

    destination="$PRIMARY_SOURCE/$skill"
    existed=0
    ([ -e "$destination" ] || [ -L "$destination" ]) && existed=1
    external_source="$(absolute_existing_dir "$entry")" || {
      warn "无法读取 skill 目录：${entry}"
      continue
    }
    import_directory_into_library "$external_source" "$skill" || continue
    if [ "$existed" -eq 0 ]; then
      adopted_skills+=("$skill")
    fi
  done
  shopt -u nullglob

  if [ "${#adopted_skills[@]}" -eq 0 ]; then
    info "  没有可收纳的新 skill"
    return 0
  fi

  if [ "$SYNC_AFTER_IMPORT" -eq 1 ]; then
    SKILL_FILTER=("${adopted_skills[@]}")
    run_sync_scope "$scope"
  fi
}

run_remove_scope() {
  local scope="$1"
  local agent target skill target_skill destination

  if [ "${#SKILL_FILTER[@]}" -eq 0 ]; then
    error "remove/disable 需要至少一个 skill 名称"
    return 1
  fi

  setup_scope "$scope" || return 1
  for skill in "${SKILL_FILTER[@]}"; do
    valid_skill_name "$skill" || {
      error "非法 skill 名称：$skill"
      continue
    }
  done

  info "移除 $scope 作用域中的目标软链（不删除源 skill）"
  for agent in "${ACTIVE_AGENTS[@]}"; do
    target="$(target_directory "$agent")"
    [ -d "$target" ] || {
      info "- $agent: 目标目录不存在，跳过"
      continue
    }
    for skill in "${SKILL_FILTER[@]}"; do
      target_skill="$target/$skill"
      if [ -L "$target_skill" ]; then
        if link_is_managed "$target_skill" || [ "$FORCE" -eq 1 ]; then
          remove_link "$target_skill" "手动禁用"
        else
          destination="$(link_destination "$target_skill" 2>/dev/null || printf '未知目标')"
          warn "保留外部软链：${target_skill} -> ${destination}（加 --force 可删除）"
          CONFLICTS=$((CONFLICTS + 1))
        fi
      elif [ -e "$target_skill" ]; then
        warn "保留真实文件或目录：$target_skill"
        CONFLICTS=$((CONFLICTS + 1))
      else
        [ "$VERBOSE" -eq 1 ] && info "  不存在：$agent/$skill"
      fi
    done
  done
}

check_source_skills() {
  local source="$1"
  local label="$2"
  local skill

  if [ ! -d "$source" ]; then
    error "$label 源目录不存在：$source"
    return 1
  fi

  collect_dir_skills "$source"
  if [ "${#COLLECTED_SKILLS[@]}" -eq 0 ]; then
    warn "$label 源目录为空：$source"
    return 0
  fi

  for skill in "${COLLECTED_SKILLS[@]}"; do
    if [ ! -f "$source/$skill/SKILL.md" ]; then
      error "$label skill 缺少 SKILL.md：$skill"
    elif [ "$VERBOSE" -eq 1 ]; then
      info "  正常：$label/$skill"
    fi
  done
}

doctor_target() {
  local target="$1"
  local agent="$2"
  local skill source target_skill entry destination

  if [ ! -d "$target" ]; then
    warn "$agent 目标目录不存在：$target"
    return 0
  fi

  for skill in "${EFFECTIVE_SKILLS[@]}"; do
    source="$(source_for_skill "$skill")" || continue
    target_skill="$target/$skill"
    if link_matches_path "$target_skill" "$source"; then
      [ "$VERBOSE" -eq 1 ] && info "  正常：$agent/$skill"
    elif [ -L "$target_skill" ]; then
      destination="$(link_destination "$target_skill" 2>/dev/null || printf '未知目标')"
      error "$agent/$skill 指向错误位置：$destination"
    elif [ -e "$target_skill" ]; then
      error "$agent/$skill 被真实文件或目录占用"
    else
      warn "$agent/$skill 尚未链接"
    fi
  done

  shopt -s nullglob
  for entry in "$target"/*; do
    skill="$(basename "$entry")"
    contains_value "$skill" "${EFFECTIVE_SKILLS[@]}" && continue
    if link_is_stale_managed "$entry"; then
      error "$agent/$skill 是失效受管软链"
    elif [ -L "$entry" ] && [ ! -e "$entry" ]; then
      warn "$agent/$skill 是失效外部软链"
    fi
  done
  shopt -u nullglob
}

run_doctor_scope() {
  local scope="$1"
  local agent target skill

  setup_scope "$scope" || return 1
  info "检查 $scope 作用域：$PRIMARY_SOURCE"
  check_source_skills "$PRIMARY_SOURCE" "主" || true
  if [ -n "$SECONDARY_SOURCE" ]; then
    check_source_skills "$SECONDARY_SOURCE" "全局继承" || true
    if [ -d "$PRIMARY_SOURCE" ] && [ -d "$SECONDARY_SOURCE" ]; then
      collect_dir_skills "$PRIMARY_SOURCE"
      local -a local_skills=("${COLLECTED_SKILLS[@]}")
      for skill in "${local_skills[@]}"; do
        if [ -d "$SECONDARY_SOURCE/$skill" ]; then
          warn "项目 skill 覆盖同名全局 skill：$skill"
        fi
      done
    fi
  fi

  build_effective_skills
  for agent in "${ACTIVE_AGENTS[@]}"; do
    target="$(target_directory "$agent")"
    doctor_target "$target" "$agent"
  done
}

run_scope_command() {
  local scope="$1"

  case "$COMMAND" in
    sync) run_sync_scope "$scope" ;;
    status) run_status_scope "$scope" ;;
    clean) run_clean_scope "$scope" ;;
    doctor) run_doctor_scope "$scope" ;;
    list) run_list_scope "$scope" ;;
    init) run_init_scope "$scope" ;;
    import) run_import_scope "$scope" ;;
    adopt) run_adopt_scope "$scope" ;;
    remove) run_remove_scope "$scope" ;;
    *) die "内部错误：未知命令 $COMMAND" ;;
  esac
}

parse_arguments() {
  local first="${1:-}"

  case "$first" in
    sync|status|clean|doctor|list|init|import|adopt|remove)
      COMMAND="$first"
      shift
      ;;
    enable)
      COMMAND="sync"
      REQUIRE_SKILL_FILTER=1
      shift
      ;;
    disable)
      COMMAND="remove"
      shift
      ;;
    help)
      usage
      exit 0
      ;;
  esac

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scope)
        [ "$#" -ge 2 ] || die "--scope 需要 global、project 或 all"
        SCOPE="$2"
        shift 2
        ;;
      --project)
        [ "$#" -ge 2 ] || die "--project 需要目录路径"
        PROJECT_ARGUMENT="$2"
        shift 2
        ;;
      --target|--agent)
        [ "$#" -ge 2 ] || die "$1 需要 Agent 名称"
        add_target_value "$2"
        shift 2
        ;;
      --dry-run|-n)
        DRY_RUN=1
        shift
        ;;
      --no-prune)
        PRUNE=0
        shift
        ;;
      --include-global)
        INCLUDE_GLOBAL=1
        shift
        ;;
      --orphaned)
        ORPHANED=1
        shift
        ;;
      --name)
        [ "$#" -ge 2 ] || die "--name 需要 skill 名称"
        IMPORT_NAME="$2"
        shift 2
        ;;
      --from)
        [ "$#" -ge 2 ] || die "--from 需要 Agent 名称"
        ADOPT_AGENT="$2"
        shift 2
        ;;
      --link)
        IMPORT_MODE="link"
        IMPORT_MODE_EXPLICIT=1
        shift
        ;;
      --copy)
        IMPORT_MODE="copy"
        IMPORT_MODE_EXPLICIT=1
        shift
        ;;
      --sync)
        SYNC_AFTER_IMPORT=1
        shift
        ;;
      --force|-f)
        FORCE=1
        shift
        ;;
      --verbose|-v)
        VERBOSE=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          SKILL_FILTER+=("$1")
          shift
        done
        ;;
      -*) die "未知选项：$1" ;;
      *)
        SKILL_FILTER+=("$1")
        shift
        ;;
    esac
  done
}

print_summary() {
  case "$COMMAND" in
    sync|clean|remove)
      info "完成：新增 ${CREATED}，更新 ${UPDATED}，删除 ${REMOVED}，未变更 ${UNCHANGED}，冲突 ${CONFLICTS}"
      ;;
    import|adopt)
      info "完成：导入 ${IMPORTED} 个 skill，新增 ${CREATED}，更新 ${UPDATED}，冲突 ${CONFLICTS}"
      ;;
  esac
}

main() {
  parse_arguments "$@"

  if [ "$REQUIRE_SKILL_FILTER" -eq 1 ] && [ "${#SKILL_FILTER[@]}" -eq 0 ]; then
    die "enable 需要至少一个 skill 名称"
  fi

  case "$SCOPE" in
    global|project)
      run_scope_command "$SCOPE"
      ;;
    all)
      run_scope_command global
      run_scope_command project
      ;;
    *) die "--scope 只能是 global、project 或 all" ;;
  esac

  print_summary
  if [ "$ISSUES" -gt 0 ]; then
    return 1
  fi
}

main "$@"

#!/usr/bin/env bash
# Simplified wrapper for DeepSeek API as a second-agent review/analysis tool.
# Usage: deepseek_collab.sh <review|challenge-diff|challenge-plan|investigate|implement> [options]
set -euo pipefail

# ── 配置（填入你自己的 key 即可使用，无需设置环境变量）──────────
DEEPSEEK_BASE_URL="https://api.deepseek.com/v1"
DEEPSEEK_MODEL="deepseek-v4-pro"
DEEPSEEK_TIMEOUT="600"
# ──────────────────────────────────────────────────────────────

export DEEPSEEK_API_KEY DEEPSEEK_BASE_URL DEEPSEEK_MODEL DEEPSEEK_TIMEOUT

usage() {
  cat >&2 <<'EOF'
Usage:
  deepseek_collab.sh review [--cwd PATH] [--dry-run]
  deepseek_collab.sh challenge-diff [--cwd PATH] [--dry-run]
  deepseek_collab.sh challenge-plan (--prompt-file FILE | prompt text...) [--cwd PATH] [--dry-run]
  deepseek_collab.sh investigate (--prompt-file FILE | prompt text...) [--cwd PATH] [--dry-run]
  deepseek_collab.sh implement (--prompt-file FILE | prompt text...) [--cwd PATH] [--dry-run]

Modes:
  review          Read-only review of current git changes.
  challenge-diff  Read-only adversarial review of current git changes.
  challenge-plan  Read-only challenge review of a plan/proposal.
  investigate     Read-only second opinion / bug diagnosis.
  implement       Read-only: suggests code changes but does NOT write files.

Configuration: edit the variables at the top of this script.
EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 2
fi

MODE="$1"
shift || true

# Resolve script directory for the Python caller
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CALLER="$SCRIPT_DIR/deepseek_call.py"

resolve_default_cwd() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

case "$MODE" in
  review|challenge-diff)
    CWD=""
    DRY_RUN=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --cwd)
          if [ $# -lt 2 ]; then echo "Missing value for --cwd" >&2; exit 2; fi
          CWD="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
      esac
    done
    if [ -z "$CWD" ]; then CWD="$(resolve_default_cwd)"; fi
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "python3 $CALLER --mode $MODE --cwd $CWD"
      exit 0
    fi
    python3 "$CALLER" --mode "$MODE" --cwd "$CWD"
    ;;
  challenge-plan|investigate|implement)
    CWD=""
    DRY_RUN=0
    PROMPT_FILE=""
    PROMPT_PARTS=()
    while [ $# -gt 0 ]; do
      case "$1" in
        --prompt-file)
          if [ $# -lt 2 ]; then echo "Missing value for --prompt-file" >&2; exit 2; fi
          PROMPT_FILE="$2"; shift 2 ;;
        --cwd)
          if [ $# -lt 2 ]; then echo "Missing value for --cwd" >&2; exit 2; fi
          CWD="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) PROMPT_PARTS+=("$1"); shift ;;
      esac
    done
    if [ -z "$CWD" ]; then CWD="$(resolve_default_cwd)"; fi
    if [ -n "$PROMPT_FILE" ]; then
      if [ ! -f "$PROMPT_FILE" ]; then
        echo "Prompt file not found: $PROMPT_FILE" >&2; exit 2
      fi
      PROMPT="$(cat "$PROMPT_FILE")"
    else
      if [ ${#PROMPT_PARTS[@]} -eq 0 ]; then
        echo "Missing prompt text or --prompt-file for $MODE" >&2; exit 2
      fi
      PROMPT="${PROMPT_PARTS[*]}"
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "python3 $CALLER --mode $MODE --cwd $CWD --prompt-text '${PROMPT:0:80}...'"
      exit 0
    fi
    python3 "$CALLER" --mode "$MODE" --cwd "$CWD" --prompt-text "$PROMPT"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown mode: $MODE" >&2; usage; exit 2 ;;
esac

#!/usr/bin/env bash
# Simplified wrapper for the OpenAI Codex Claude Code plugin.
# Usage: codex_collab.sh <setup|review|challenge-diff|challenge-plan|investigate|implement|status|result|cancel> [options]
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  codex_collab.sh setup [--json]
  codex_collab.sh review [codex review args...]
  codex_collab.sh challenge-diff [codex adversarial-review args...]
  codex_collab.sh challenge-plan (--prompt-file FILE | prompt text...) [--background] [--effort VALUE] [--model MODEL] [--cwd PATH] [--dry-run]
  codex_collab.sh investigate (--prompt-file FILE | prompt text...) [--background] [--effort VALUE] [--model MODEL] [--cwd PATH] [--dry-run]
  codex_collab.sh implement (--prompt-file FILE | prompt text...) [--background] [--effort VALUE] [--model MODEL] [--cwd PATH] [--dry-run]
  codex_collab.sh status [job-id] [--all] [--wait]
  codex_collab.sh result [job-id]
  codex_collab.sh cancel [job-id]

Modes:
  review          Read-only review of current git changes.
  challenge-diff  Read-only adversarial review of current git changes.
  challenge-plan  Read-only challenge review of a plan/proposal.
  investigate     Read-only second opinion / bug diagnosis.
  implement       Write-capable small scoped task.
EOF
}

if [ $# -lt 1 ]; then
  usage
  exit 2
fi

MODE="$1"
shift || true

if ! command -v codex >/dev/null 2>&1; then
  echo "Codex CLI not found. Install Codex and add the openai/codex-plugin-cc marketplace first." >&2
  exit 1
fi

PLUGIN_ROOT="$(codex plugin list --marketplace openai-codex --json | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as exc:
    raise SystemExit(f"Failed to parse codex plugin list JSON: {exc}")
for plugin in data.get("installed", []):
    if plugin.get("pluginId") == "codex@openai-codex" and plugin.get("enabled"):
        print(plugin.get("source", {}).get("path", ""))
        break
')"

if [ -z "$PLUGIN_ROOT" ] || [ ! -f "$PLUGIN_ROOT/scripts/codex-companion.mjs" ]; then
  echo "codex@openai-codex plugin is not installed/enabled. Run:" >&2
  echo "  codex plugin marketplace add openai/codex-plugin-cc" >&2
  echo "  codex plugin add codex@openai-codex" >&2
  exit 1
fi

COMPANION="$PLUGIN_ROOT/scripts/codex-companion.mjs"

run_companion() {
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" node "$COMPANION" "$@"
}

resolve_default_cwd() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

run_task_mode() {
  local task_mode="$1"
  shift

  local background=0
  local dry_run=0
  local effort="${CODEX_COLLAB_EFFORT:-medium}"
  local model=""
  local cwd=""
  local prompt_file=""
  local prompt_parts=()

  while [ $# -gt 0 ]; do
    case "$1" in
      --background)
        background=1
        shift
        ;;
      --effort)
        if [ $# -lt 2 ]; then echo "Missing value for --effort" >&2; exit 2; fi
        effort="$2"
        shift 2
        ;;
      --model)
        if [ $# -lt 2 ]; then echo "Missing value for --model" >&2; exit 2; fi
        model="$2"
        shift 2
        ;;
      --cwd)
        if [ $# -lt 2 ]; then echo "Missing value for --cwd" >&2; exit 2; fi
        cwd="$2"
        shift 2
        ;;
      --prompt-file)
        if [ $# -lt 2 ]; then echo "Missing value for --prompt-file" >&2; exit 2; fi
        prompt_file="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        prompt_parts+=("$1")
        shift
        ;;
    esac
  done

  if [ -z "$cwd" ]; then
    cwd="$(resolve_default_cwd)"
  fi

  local cmd=(node "$COMPANION" task --fresh --cwd "$cwd" --effort "$effort")
  if [ -n "$model" ]; then
    cmd+=(--model "$model")
  fi
  if [ "$background" -eq 1 ]; then
    cmd+=(--background)
  fi
  if [ "$task_mode" = "implement" ]; then
    cmd+=(--write)
  fi

  if [ -n "$prompt_file" ]; then
    if [ ! -f "$prompt_file" ]; then
      echo "Prompt file not found: $prompt_file" >&2
      exit 2
    fi
    cmd+=(--prompt-file "$prompt_file")
  else
    if [ ${#prompt_parts[@]} -eq 0 ]; then
      echo "Missing prompt text or --prompt-file for $task_mode" >&2
      exit 2
    fi
    local prompt="${prompt_parts[*]}"
    case "$task_mode" in
      challenge-plan)
        prompt=$'<task>Challenge this implementation plan. This is read-only. Do not edit files.</task>\n\n'"$prompt"$'\n\n<output_contract>Return findings first, ordered P0/P1/P2/P3, then recommended implementation shape and validation.</output_contract>'
        ;;
      investigate)
        prompt=$'<task>Investigate this issue. This is read-only. Do not edit files.</task>\n\n'"$prompt"$'\n\n<output_contract>Return observed facts, likely root cause, evidence, suggested fix direction, and validation.</output_contract>'
        ;;
      implement)
        prompt=$'<task>Implement this small scoped change.</task>\n\n'"$prompt"$'\n\n<constraints>Keep changes surgical, preserve unrelated user changes, follow existing conventions, and run focused validation if feasible.</constraints>'
        ;;
    esac
    cmd+=("$prompt")
  fi

  if [ "$dry_run" -eq 1 ]; then
    printf 'CLAUDE_PLUGIN_ROOT=%q ' "$PLUGIN_ROOT"
    printf '%q ' "${cmd[@]}"
    printf '\n'
    return 0
  fi

  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" "${cmd[@]}"
}

case "$MODE" in
  setup)
    run_companion setup "$@"
    ;;
  review)
    run_companion review "$@"
    ;;
  challenge-diff|adversarial-review)
    run_companion adversarial-review "$@"
    ;;
  challenge-plan)
    run_task_mode challenge-plan "$@"
    ;;
  investigate|second-opinion|bugcheck)
    run_task_mode investigate "$@"
    ;;
  implement|task)
    run_task_mode implement "$@"
    ;;
  status)
    run_companion status "$@"
    ;;
  result)
    run_companion result "$@"
    ;;
  cancel)
    run_companion cancel "$@"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    usage
    exit 2
    ;;
esac

#!/usr/bin/env python3
"""Call DeepSeek API for code review / plan review / investigation.

DeepSeek API is OpenAI-compatible. This script:
- For review / challenge-diff: gathers git diff context, sends a review prompt
- For challenge-plan / investigate / implement: sends the user prompt directly
- All modes are read-only from the script's perspective.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import textwrap

# ── defaults ──────────────────────────────────────────────────
DEFAULT_BASE_URL = "https://api.deepseek.com/v1"
DEFAULT_MODEL = "deepseek-v4-pro"
# 填入你自己的 API Key（优先于环境变量 DEEPSEEK_API_KEY）
INLINE_API_KEY = ""
# ──────────────────────────────────────────────────────────────
MAX_DIFF_BYTES = 120_000  # keep prompt under context limit


def get_api_key() -> str:
    # 优先取脚本内置 key，其次取环境变量
    key = (INLINE_API_KEY or os.environ.get("DEEPSEEK_API_KEY", "")).strip()
    if not key:
        print("DEEPSEEK_API_KEY 未设置。请在脚本顶部 INLINE_API_KEY 填入你的 key。", file=sys.stderr)
        sys.exit(1)
    return key


def get_base_url() -> str:
    return os.environ.get("DEEPSEEK_BASE_URL", DEFAULT_BASE_URL).rstrip("/")


def get_model() -> str:
    return os.environ.get("DEEPSEEK_MODEL", DEFAULT_MODEL)


def gather_git_diff(cwd: str) -> str:
    """Gather staged + unstaged diff for review modes."""
    diff_parts: list[str] = []

    try:
        staged = subprocess.run(
            ["git", "-C", cwd, "diff", "--cached", "--stat"],
            capture_output=True, text=True, timeout=15,
        )
        if staged.stdout.strip():
            diff_parts.append("## Staged changes\n```\n" + staged.stdout.strip() + "\n```")

        unstaged = subprocess.run(
            ["git", "-C", cwd, "diff", "--stat"],
            capture_output=True, text=True, timeout=15,
        )
        if unstaged.stdout.strip():
            diff_parts.append("## Unstaged changes\n```\n" + unstaged.stdout.strip() + "\n```")

        # Include full diffs for files actually changed
        full_diff = subprocess.run(
            ["git", "-C", cwd, "diff", "--cached", "--", ":(exclude)pnpm-lock.yaml", ":(exclude)*.lock"],
            capture_output=True, text=True, timeout=15,
        )
        if full_diff.stdout.strip():
            diff_parts.append("## Full diff (staged)\n```diff\n" + full_diff.stdout.strip()[:MAX_DIFF_BYTES] + "\n```")

        full_unstaged = subprocess.run(
            ["git", "-C", cwd, "diff", "--", ":(exclude)pnpm-lock.yaml", ":(exclude)*.lock"],
            capture_output=True, text=True, timeout=15,
        )
        if full_unstaged.stdout.strip():
            diff_parts.append("## Full diff (unstaged)\n```diff\n" + full_unstaged.stdout.strip()[:MAX_DIFF_BYTES] + "\n```")
    except Exception as exc:
        diff_parts.append(f"(git diff failed: {exc})")

    return "\n\n".join(diff_parts) if diff_parts else "(no changes detected)"


REVIEW_SYSTEM = textwrap.dedent("""\
You are a careful code reviewer. Your task is to review code changes and report findings.

Rules:
- Return findings ordered by severity: P0 (critical), P1 (high), P2 (medium), P3 (low).
- For each finding, include: severity, risk, evidence from the diff, and recommended fix.
- If there are no findings, say so explicitly.
- Be precise: reference specific files and line numbers where visible.
- Do not fix issues. Do not suggest edits. Only report findings.
""")

CHALLENGE_DIFF_SYSTEM = textwrap.dedent("""\
You are an adversarial code reviewer. Your task is to challenge the current implementation approach,
design choices, tradeoffs, and assumptions — not just find surface defects.

Rules:
- Question whether the chosen approach is the right one.
- Identify assumptions the code depends on.
- Point out where the design could fail under real-world conditions (scale, concurrency, edge cases).
- Return findings ordered by severity: P0/P1/P2/P3.
- Include evidence, risk, and recommended adjustment for each finding.
- Do not fix issues. Only report findings.
""")

CHALLENGE_PLAN_SYSTEM = textwrap.dedent("""\
You are an architectural reviewer. Your task is to challenge a proposed implementation plan.

Rules:
- Review fit with existing architecture and conventions.
- Identify startup / import-order / concurrency / state persistence / failure recovery risks.
- Surface security or supply-chain concerns.
- Flag missing tests or smoke checks.
- Suggest simpler implementation paths where applicable.
- Return findings ordered by severity: P0/P1/P2/P3.
- Include evidence, risk, and recommended adjustment.
- End with recommended implementation shape and validation.
""")

INVESTIGATE_SYSTEM = textwrap.dedent("""\
You are a debugging assistant. Your task is to investigate an issue and provide a diagnosis.

Rules:
- Ground every claim in evidence. If you cannot be certain, separate facts from hypotheses.
- Return: observed facts, likely root cause, evidence, suggested fix direction, and validation to run.
- Be concise. Do not edit files.
""")

IMPLEMENT_SYSTEM = textwrap.dedent("""\
You are a coding assistant. Your task is to suggest a small scoped code change.

Rules:
- Suggest minimal, surgical changes.
- Preserve existing conventions and patterns.
- Include exact file paths and the suggested diff.
- Note: you are suggesting code. A human or agent will review and apply it.
""")

SYSTEM_PROMPTS = {
    "review": REVIEW_SYSTEM,
    "challenge-diff": CHALLENGE_DIFF_SYSTEM,
    "challenge-plan": CHALLENGE_PLAN_SYSTEM,
    "investigate": INVESTIGATE_SYSTEM,
    "implement": IMPLEMENT_SYSTEM,
}


def build_user_prompt(mode: str, cwd: str, user_text: str) -> str:
    if mode in ("review", "challenge-diff"):
        diff = gather_git_diff(cwd)
        return f"Repository: {cwd}\n\n## Git changes\n\n{diff}\n\n## User notes\n\n{user_text}"
    return user_text


def call_deepseek(api_key: str, base_url: str, model: str, system: str, user: str) -> str:
    """Call DeepSeek API via HTTP (stdlib only, no openai dependency needed)."""
    import urllib.request

    body = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "stream": False,
    }).encode("utf-8")

    req = urllib.request.Request(
        f"{base_url}/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    timeout = int(os.environ.get("DEEPSEEK_TIMEOUT", "180"))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            data = json.load(resp)
    except urllib.error.HTTPError as exc:
        try:
            err_body = json.load(exc)
        except Exception:
            err_body = {}
        msg = err_body.get("error", {}).get("message", str(exc))
        return f"DeepSeek API error (HTTP {exc.code}): {msg}"
    except Exception as exc:
        return f"DeepSeek API error: {exc}"

    choices = data.get("choices", [])
    if not choices:
        return f"DeepSeek returned no choices. Raw: {json.dumps(data, indent=2)[:500]}"

    content = choices[0].get("message", {}).get("content", "")
    if not content:
        return f"DeepSeek returned empty content. Raw: {json.dumps(choices[0], indent=2)[:500]}"

    # Print usage info to stderr so it doesn't interfere with stdout
    usage = data.get("usage", {})
    if usage:
        print(
            f"[deepseek] tokens: {usage.get('prompt_tokens', '?')} in / {usage.get('completion_tokens', '?')} out",
            file=sys.stderr,
        )

    return content


def main() -> None:
    parser = argparse.ArgumentParser(description="DeepSeek Collab — second-agent review/analysis")
    parser.add_argument("--mode", required=True, choices=list(SYSTEM_PROMPTS))
    parser.add_argument("--cwd", default=os.getcwd())
    parser.add_argument("--prompt-text", default="")
    parser.add_argument("--prompt-file")
    args = parser.parse_args()

    user_text = args.prompt_text
    if args.prompt_file:
        with open(args.prompt_file, encoding="utf-8") as f:
            user_text = f.read()
    if not user_text.strip():
        user_text = "Please review the changes."

    api_key = get_api_key()
    base_url = get_base_url()
    model = get_model()
    system = SYSTEM_PROMPTS[args.mode]
    user = build_user_prompt(args.mode, args.cwd, user_text)

    print(call_deepseek(api_key, base_url, model, system, user))


if __name__ == "__main__":
    main()

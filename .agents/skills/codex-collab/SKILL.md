---
name: codex-collab
description: Simplified wrapper around the OpenAI Codex Claude Code plugin for practical second-agent workflows in any repository. Use when the user wants Codex to review current changes, challenge a plan or architecture, provide a second opinion, investigate a bug read-only, implement a small scoped change, or check/cancel Codex background jobs. Trigger phrases include "让 Codex review", "挑战这个方案", "问 Codex", "让 Codex 查 bug", "派给 Codex", "Codex 第二意见", and "Codex 帮我实现一个小改动".
---

# Codex Collab

Use this skill as a **single simplified interface** to the installed `codex@openai-codex` plugin. Do not expose the plugin's full complexity unless the user asks.

## Intent router

Choose the smallest mode that matches the user's request:

| User intent | Mode | Mutates files? | Command |
|---|---|---:|---|
| Review current git changes | `review` | No | `scripts/codex_collab.sh review ...` |
| Challenge a plan/design | `challenge-plan` | No | `scripts/codex_collab.sh challenge-plan --prompt-file FILE` |
| Challenge current implementation/diff | `challenge-diff` | No | `scripts/codex_collab.sh challenge-diff ...` |
| Get second opinion or inspect a bug | `investigate` | No | `scripts/codex_collab.sh investigate ...` |
| Let Codex implement a small scoped change | `implement` | Yes | `scripts/codex_collab.sh implement ...` |
| See progress/output/cancel | `status` / `result` / `cancel` | No | `scripts/codex_collab.sh status` |

## Operating rules

- Prefer `review` after code has changed.
- Prefer `challenge-plan` before code has changed.
- Prefer `investigate` when the user wants Codex to diagnose, critique, or provide a second opinion but **not** edit.
- Use `implement` only when the user explicitly asks Codex to make a small scoped change.
- Do not run two write-capable Codex tasks in the same repository at the same time.
- After a Codex review or investigation, do not auto-fix. Ask which findings to implement.
- If Codex implements code, inspect the resulting diff and run relevant verification before reporting success.

## Common commands

Run from the target repository root. The script defaults `--cwd` to the current git root.

```bash
# Setup / health check
.pi/skills/codex-collab/scripts/codex_collab.sh setup

# Review current working tree or branch changes
.pi/skills/codex-collab/scripts/codex_collab.sh review --wait
.pi/skills/codex-collab/scripts/codex_collab.sh review --base main --wait

# Challenge current diff more aggressively
.pi/skills/codex-collab/scripts/codex_collab.sh challenge-diff --wait

# Challenge a plan file
.pi/skills/codex-collab/scripts/codex_collab.sh challenge-plan --prompt-file /tmp/plan.md

# Read-only investigation / second opinion
.pi/skills/codex-collab/scripts/codex_collab.sh investigate "Find the likely cause of this bug. Do not edit files."

# Small write-capable task
.pi/skills/codex-collab/scripts/codex_collab.sh implement "Fix the narrow issue in X. Keep changes minimal and run focused validation."

# Background jobs
.pi/skills/codex-collab/scripts/codex_collab.sh status
.pi/skills/codex-collab/scripts/codex_collab.sh result JOB_ID
.pi/skills/codex-collab/scripts/codex_collab.sh cancel JOB_ID
```

Useful flags for `challenge-plan`, `investigate`, and `implement`:

```bash
--prompt-file FILE
--background
--effort none|minimal|low|medium|high|xhigh
--model MODEL_OR_ALIAS
--cwd /path/to/repo
--dry-run
```

## Prompt templates

Use `references/prompt-templates.md` when drafting a prompt file for `challenge-plan`, `investigate`, or `implement`.

## Installation dependency

This skill assumes the OpenAI Codex plugin is installed:

```bash
codex plugin marketplace add openai/codex-plugin-cc
codex plugin add codex@openai-codex
```

The wrapper script auto-discovers the installed plugin path with `codex plugin list --marketplace openai-codex --json`.

## Portability

This skill is repository-agnostic. To reuse it elsewhere, copy the whole `codex-collab/` directory into:

- Project-local: `.pi/skills/codex-collab/`
- Global pi: `~/.pi/agent/skills/codex-collab/`
- Shared agents: `~/.agents/skills/codex-collab/`

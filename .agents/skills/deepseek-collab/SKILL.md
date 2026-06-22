---
name: deepseek-collab
description: Second-agent review and analysis via DeepSeek API. Use when the user wants DeepSeek to review current changes, challenge a plan or architecture, provide a second opinion, investigate a bug read-only, or suggest implementation for a small scoped change. Also use when the user mentions "用 DeepSeek review", "DeepSeek 第二意见", "让 DeepSeek 查", "DeepSeek 审查方案", or wants a lighter faster alternative to Codex for read-only analysis. All modes are read-only from the API's perspective — use codex-collab when Codex needs to write files.
---

# DeepSeek Collab

Use this skill as a **single simplified interface** to the DeepSeek API for second-agent review and analysis. Unlike codex-collab, all modes are read-only from the API's perspective — DeepSeek can suggest code but cannot edit files, run commands, or manage background jobs.

## Intent router

Choose the smallest mode that matches the user's request:

| User intent | Mode | What it does |
|---|---|---|
| Review current git changes | `review` | Gathers git diff, sends review prompt |
| Challenge a plan/design | `challenge-plan` | Sends the plan/proposal for architectural challenge |
| Challenge current implementation/diff | `challenge-diff` | Gathers git diff, sends adversarial review prompt |
| Get second opinion or inspect a bug | `investigate` | Sends the issue for diagnosis |
| Suggest implementation for a small change | `implement` | Suggests code changes but does NOT write files |

## Requirements

编辑 `scripts/deepseek_collab.sh` 顶部，填入你的 key：

```bash
DEEPSEEK_API_KEY="sk-..."               # 必填
DEEPSEEK_BASE_URL="https://api.deepseek.com/v1"   # 可选，默认值如上
DEEPSEEK_MODEL="deepseek-chat"                     # 可选
DEEPSEEK_TIMEOUT="180"                             # 可选，秒
```

无需设置环境变量。

## Commands

Run from the target repository root.

```bash
# Review current git changes
.pi/skills/deepseek-collab/scripts/deepseek_collab.sh review

# Challenge current diff more aggressively
.pi/skills/deepseek-collab/scripts/deepseek_collab.sh challenge-diff

# Challenge a plan file
.pi/skills/deepseek-collab/scripts/deepseek_collab.sh challenge-plan --prompt-file /tmp/plan.md

# Investigate a bug / second opinion
.pi/skills/deepseek-collab/scripts/deepseek_collab.sh investigate "Why does this test fail? Do not edit."

# Suggest a small code change
.pi/skills/deepseek-collab/scripts/deepseek_collab.sh implement "Change the retry logic to use exponential backoff."
```

Useful flags:

```bash
--prompt-file FILE    # Read prompt from file instead of inline text
--cwd PATH            # Repository root (default: git root or pwd)
--dry-run             # Print the resolved command without calling the API
```

## Operating rules

- Prefer `review` after code has changed. The script auto-gathers git diff context.
- Prefer `challenge-plan` before code has changed.
- Prefer `investigate` when the user wants diagnosis or a second opinion.
- Use `implement` only for suggesting code — it cannot edit files.
- After a review or investigation, present Codex's output clearly. Do not auto-fix. Ask which findings to implement.
- If DeepSeek returns an error (auth, rate limit, timeout), report it and stop.

## Comparison with codex-collab

| Capability | codex-collab | deepseek-collab |
|---|---|---|
| Read code from repo | Yes (agent loop) | Only via git diff context |
| Write files | Yes (implement mode) | No (suggest only) |
| Run commands / tests | Yes | No |
| Background jobs | Yes | No |
| Review current diff | Yes | Yes |
| Challenge plans | Yes | Yes |
| Speed | Moderate (agent loop) | Fast (single API call) |
| Cost | Codex credits | DeepSeek API tokens |

Use deepseek-collab when you want a fast, cheap read-only second opinion. Use codex-collab when you need Codex to actually read files, run commands, or write code.

## Prompt templates

Use `references/prompt-templates.md` when drafting prompts for `challenge-plan`, `investigate`, or `implement`.

## Portability

This skill is repository-agnostic. To reuse it elsewhere, copy the whole `deepseek-collab/` directory into:

- Project-local: `.pi/skills/deepseek-collab/`
- Global pi: `~/.pi/agent/skills/deepseek-collab/`
- Shared agents: `~/.agents/skills/deepseek-collab/`

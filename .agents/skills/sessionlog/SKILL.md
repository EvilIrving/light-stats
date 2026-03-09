---
name: sessionlog
version: 1.1.0
description: Save durable project knowledge into sessionlog.md. Use after important discussion, design decision, bugfix, workflow change, or when user asks to log session.
allowed-tools: 
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - AskUserQuestion
---

# Project Log Skill

Maintain `sessionlog.md` as long-term project knowledge.

This log stores **durable knowledge**, not conversation history.

Use this skill when:

- design decision finished
- bug fixed with reasoning
- workflow changed
- prompt / agent / tool updated
- user asks to save session
- session contains reusable knowledge


## Goal

Keep sessionlog.md clean, short, and useful.

Prefer:

- decisions over discussion
- summary over transcript
- short over long
- merge over append


## Target file

sessionlog.md


## Steps

1. Read sessionlog.md if exists
2. Extract useful knowledge from current conversation
3. Ignore temporary debugging
4. Ignore unrelated content
5. Generate short summary
6. Check if similar topic exists
7. If similar → merge
8. If not → create new entry
9. Keep newest info
10. Remove redundancy
11. Write file back


## Similarity rules

Two entries are similar if:

- same topic
- same feature
- same file
- same decision
- same bug
- same prompt / agent / workflow

If similar:

- merge instead of append
- keep newest decision
- keep both if conflict
- compress old text


## Format

New entries must be added at top.

Format:

## <title>

time: <datetime>

source: claude-code

topic: <short topic>

tags: [design, bugfix, workflow, prompt, agent, build, refactor, config]

summary:
<short summary>

decisions:
- ...

notes:
- ...

reason:
- why decision made
- tradeoff
- risk

refs:
- file
- command
- prompt
- link


## Rules

- max 200 words per entry
- do not log full conversation
- do not log small talk
- do not log failed attempts
- keep entries readable
- keep newest at top
- merge similar entries
- remove duplicated text


## File limits

Prefer file < 2000 lines

If too long:

- compress old entries
- keep summaries only
- keep recent full entries


## Title

Use:

$ARGUMENTS

If empty:

Generate title automatically


## Output

Write updated sessionlog.md only.

Do not explain.
Do not chat.
Do not add comments.
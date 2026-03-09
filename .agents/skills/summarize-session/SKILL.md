---
name: summarize-session
description: Summarize the current agent conversation into a structured session summary for logs or notes.
disable-model-invocation: true
allowed-tools: Read
---

# Session Summary Skill

Summarize the current conversation into a structured, concise summary.

Use this skill when:

- finishing a session
- before writing sessionlog.md
- before commit / PR
- when user asks to summarize
- when conversation is long
- when important decisions were made


## Task

Summarize the current agent conversation.

Only include information that actually happened.


## Output format

### Title
A descriptive title for this conversation (6 words or fewer).

### Goal
What the user was trying to accomplish (1–2 sentences).

### Key Decisions
- Each significant decision
- Include reasoning or trade-offs

### Actions Taken
- Files created / modified
- Commands executed
- Config changed
- Include paths

### Outcome
Final result (1–2 sentences)

### Open Items
- unresolved issues
- TODO
- limitations

### Technical Context
- tools
- libraries
- APIs
- patterns
- important files


## Rules

1. Be factual.
2. Be concise.
3. Preserve specifics.
4. Skip empty sections.
5. If conversation is informational only:
   use "Key Findings" instead of Actions/Outcome.
6. Use the same language as the conversation.
7. Do not invent actions.
8. Do not include chat filler.


## Scope

Summarize only the current conversation context.

Do not read unrelated files.

Do not modify files.

Return summary only.
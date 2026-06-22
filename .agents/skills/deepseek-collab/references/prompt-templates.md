# DeepSeek Collab Prompt Templates

Use these as prompt files for `challenge-plan`, `investigate`, and `implement`.
For `review` and `challenge-diff`, the script auto-gathers git diff context.

## Challenge plan

```xml
<task>
Challenge this implementation plan for the repository at <REPOSITORY_PATH>. This is read-only. Do not suggest edits.
</task>

<context>
- Product/repo: <brief description>
- Relevant existing facts from files already inspected:
  - <fact with file path if known>
- Non-goals:
  - <what should not be implemented>
</context>

<proposed_plan>
1. <step>
2. <step>
3. <step>
</proposed_plan>

<review_request>
Review fit with architecture, correctness, edge cases, concurrency/state, security, user experience, and validation. Prefer simpler adjustments when possible.
</review_request>

<output_contract>
Return findings first, ordered P0/P1/P2/P3. Each finding must include evidence, risk, and recommended adjustment. Then include recommended implementation shape and validation.
</output_contract>
```

## Investigate bug, read-only

```xml
<task>
Investigate this bug in the repository at <REPOSITORY_PATH>. This is read-only. Do not suggest edits.
</task>

<bug>
<symptom, error, logs, reproduction steps, or observed behavior>
</bug>

<constraints>
- Do not modify files.
- Ground claims in inspected evidence.
- If the root cause is uncertain, separate facts from hypotheses.
</constraints>

<output_contract>
Return: observed facts, likely root cause, evidence, suggested fix direction, and validation to run.
</output_contract>
```

## Small implementation suggestion

```xml
<task>
Suggest a small scoped code change for the repository at <REPOSITORY_PATH>. This is a suggestion only — do not attempt to edit files.
</task>

<scope>
<exact requested behavior>
</scope>

<constraints>
- Keep changes surgical.
- Preserve unrelated user changes.
- Follow existing project conventions.
- Include specific file paths and diff suggestions.
</constraints>

<output_contract>
Return: touched files, suggested changes (as diff or code blocks), behavioral effect, and validation to run.
</output_contract>
```

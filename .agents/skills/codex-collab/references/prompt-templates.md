# Codex Collab Prompt Templates

Use these as compact prompt files for `challenge-plan`, `investigate`, and `implement`.

## Challenge plan

```xml
<task>
Challenge this implementation plan for the repository at <REPOSITORY_PATH>. This is read-only. Do not edit files.
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
Investigate this bug in the repository at <REPOSITORY_PATH>. This is read-only. Do not edit files.
</task>

<bug>
<symptom, error, logs, reproduction steps, or observed behavior>
</bug>

<constraints>
- Do not modify files.
- Ground claims in inspected files, logs, or command output.
- If the root cause is uncertain, separate facts from hypotheses.
</constraints>

<output_contract>
Return: observed facts, likely root cause, evidence, suggested fix direction, and validation to run.
</output_contract>
```

## Small implementation

```xml
<task>
Implement this small scoped change in the repository at <REPOSITORY_PATH>.
</task>

<scope>
<exact requested behavior>
</scope>

<constraints>
- Keep changes surgical.
- Preserve unrelated user changes.
- Follow existing project conventions.
- Run focused validation if feasible.
</constraints>

<output_contract>
Return touched files, behavioral change, validation run, and any remaining caveats.
</output_contract>
```

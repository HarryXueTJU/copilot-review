# Copilot Comment Evaluation Prompt

Evaluate Copilot review comments that have not yet been handled (i.e., their ID
is absent from `handledComments` in the state file).

## Context Gathering

Before evaluating, gather all relevant context:

1. Read the source file at `{path}` around `{line}` — include ~20 lines of context
2. Read the nearest `AGENTS.md` (walk up from the file's directory; if none
   found, note that and proceed without project-specific conventions)
3. Review the diff hunk for what changed at this location

## Input

- **Comment body:** `{body}`
- **File path:** `{path}`
- **Line:** `{line}`
- **Diff hunk:** `{diff_hunk}`
- **Current round:** `{round}` (from state file)
- **Previously rejected comments:** `{priorRejections}` (JSON array of
  `{file, line, topic}` from `handledComments` where `action == "rejected"`)

## Evaluation Rules

Apply these rules in order. The first matching rule determines the outcome:

1. **Repeat detection**: Same file:line and same topic as a previously rejected
   comment. → `decision: "reject"`, cite the prior reasoning.

2. **Breakage check**: Would this change break existing functionality, tests, or
   conventions? → `decision: "reject"`, explain what would break.

3. **YAGNI check**: Is this adding a feature or abstraction that has no callers?
   → `decision: "reject"`, note the feature is unused.

4. **Confidence assessment**: Is the codebase context clear enough to be certain?
   If the comment is ambiguous, the surrounding code is unclear, or the
   suggestion could reasonably go either way → `confidence: "low"`.

## Decision Rules

Apply these rules in order (first match wins). Higher rows have priority.

| Priority | Condition | Action |
|----------|-----------|--------|
| 1 | severity = "critical" | `decision: "accept"` — always accept, regardless of confidence |
| 2 | Same file:line + same topic as prior rejection | `decision: "reject"`, cite previous reasoning |
| 3 | confidence = "low" and severity != "critical" | `decision: "reject"`, explain the uncertainty |
| 4 | severity = "minor" + round >= 3 | `decision: "reject"`, reason: "diminishing returns" |
| 5 | severity = "important" + confidence = "high" | `decision: "accept"` — confirmed bug or gap |
| 6 | (default — no condition above matched) | `decision: "accept"` — clearly beneficial change |

The `replyText` field must include either the action being taken (accepted) or
the technical reason for rejection.

## Output Format

Return ONLY a JSON object (no markdown fences, no surrounding text):

For accepted:

```json
{
  "decision": "accept",
  "severity": "important",
  "confidence": "high",
  "reasoning": "The null check is genuinely missing — `result` can be undefined at line 38 as the previous assignment uses optional chaining without a fallback.",
  "replyText": "Fixed by adding null guard at line 42."
}
```

For rejected:

```json
{
  "decision": "reject",
  "severity": "minor",
  "confidence": "high",
  "reasoning": "The suggested rename violates the project naming convention — internal methods use a leading underscore prefix per AGENTS.md.",
  "replyText": "The current name follows project convention. Internal visibility is handled by the `private` keyword, not name suffixing."
}
```

## Severity Definitions

- **critical**: Security vulnerability, data loss, crash, broken core
  functionality. Always accept.
- **important**: Logic bug, missing error handling, test gap, performance issue.
- **minor**: Naming suggestion, style preference, comment clarity, code
  organization. Accept only if clearly better.

## No Performative Agreement

Per `receiving-code-review`:
- Do NOT say "great point" or "good catch" in replyText
- State the technical action taken or the technical reason for rejection
- Actions speak louder than words

# Copilot Comment Evaluation Prompt

Feed each unhandled Copilot comment through this evaluation. The agent MUST:

1. Read the source file around the commented line
2. Read the nearest `AGENTS.md` for project conventions
3. Check the diff hunk for context on what changed
4. Output a structured JSON decision

## Input

- **Comment body:** `{body}`
- **File path:** `{path}`
- **Line:** `{line}`
- **Diff hunk:** `{diff_hunk}`
- **Source code around line:** read from the file at `{path}`, include ~20 lines of context
- **Project conventions:** read from nearest `AGENTS.md`
- **Previously rejected comments:** `{priorRejections}` (JSON array of `{file, line, topic}`)

## Evaluation Rules

Apply these rules in order (from `receiving-code-review` skill):

1. **Verify against codebase**: Does the suggested change actually fix a real problem? Read the source file and surrounding code to confirm.

2. **Check for breakage**: Would this change break existing functionality, tests, or conventions?

3. **YAGNI check**: Is this adding a feature or abstraction that isn't needed? If nothing calls it, reject.

4. **Confidence assessment**: How certain are you that this change is correct? If the comment is ambiguous, the codebase context is unclear, or the suggestion could go either way, your confidence is LOW.

5. **Repeat detection**: Is this the same topic at the same file:line as a previously rejected comment? If yes, auto-reject.

## Decision Rules

| Condition | Action |
|-----------|--------|
| confidence = "low" | `decision: "reject"`, explain uncertainty |
| Same file:line + same topic as prior rejection | `decision: "reject"`, cite previous reasoning |
| severity = "minor" + round >= 3 | `decision: "reject"`, reason: "diminishing returns" |
| severity = "critical" | `decision: "accept"` regardless of confidence |
| decision = "reject" | Provide technical reasoning in `replyText` |

## Output Format

Return ONLY a JSON object (no markdown fences, no surrounding text):

```json
{
  "decision": "accept",
  "severity": "important",
  "confidence": "high",
  "reasoning": "The null check is genuinely missing — `result` can be undefined at line 38 as the previous assignment uses optional chaining without a fallback.",
  "replyText": "Added null guard at line 42. [commit: <sha>]"
}
```

For rejected:

```json
{
  "decision": "reject",
  "severity": "minor",
  "confidence": "high",
  "reasoning": "The suggested rename from `handleTimedOutCallbacks` to `handleTimedOutCallbacksInternal` violates the project naming convention — internal methods use a leading underscore prefix per AGENTS.md.",
  "replyText": "The current name follows project convention. Internal visibility is handled by the `private` keyword, not name suffixing. See AGENTS.md naming conventions."
}
```

## Severity Definitions

- **critical**: Security vulnerability, data loss, crash, broken core functionality. Always accept.
- **important**: Logic bug, missing error handling, test gap, performance issue. Accept if confident.
- **minor**: Naming suggestion, style preference, comment clarity, code organization. Accept only if clearly better.

## No Performative Agreement

Per `receiving-code-review`:
- Do NOT say "great point" or "good catch" in replyText
- State the technical action taken or the technical reason for rejection
- Actions speak louder than words

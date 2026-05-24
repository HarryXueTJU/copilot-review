## State File

Located at `~/.claude/copilot-review/<owner>-<repo>-<pr_number>.json`.

### Schema

```json
{
  "prNumber": 1485,
  "owner": "TheDeltaLab",
  "repo": "trinity",
  "currentState": "COLLECT",
  "round": 2,
  "lastReviewId": 4350842081,
  "handledComments": {
    "3292900781": {
      "action": "accepted",
      "commitSha": "abc123",
      "file": "packages/platform/src/job/pipeline/__tests__/pipelineScheduler.test.ts",
      "line": null,
      "decision": "accept",
      "severity": "important",
      "confidence": "high"
    },
    "3292900786": {
      "action": "rejected",
      "reason": "The retry logic is intentional — see AGENTS.md concurrency section",
      "topic": "error handling",
      "decision": "reject",
      "severity": "minor",
      "confidence": "medium"
    }
  },
  "roundSummaries": [
    {"round": 1, "accepted": 3, "rejected": 1}
  ],
  "ciStatus": "passing",
  "ciFixFiles": [],
  "smartExit": {
    "consecutiveNoAction": 0
  }
}
```

### Init (create if missing)

Discover PR from current directory:
```bash
owner=$(git remote get-url origin | sed 's|.*[:/]\([^/]*\)/\([^/.]*\).*|\1|')
repo=$(git remote get-url origin | sed 's|.*[:/][^/]*/\([^/.]*\).*|\1|')
```

Detect PR number: if the current branch has an open PR, extract its number; otherwise prompt the user.

State file path: `~/.claude/copilot-review/${owner}-${repo}-${prNumber}.json`

If the file does not exist, create it with `currentState: "INIT"`, empty `handledComments`, round 0.

### Save

Write the JSON blob back to the state file after every state transition. Use:
```bash
echo '<json>' > ~/.claude/copilot-review/${owner}-${repo}-${prNumber}.json
```

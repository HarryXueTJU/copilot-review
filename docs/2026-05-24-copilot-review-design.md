# Copilot Review Skill — Design Doc

## Objective

Automate the GitHub PR review loop with Copilot: assign Copilot as reviewer,
evaluate its comments, accept reasonable ones (implement + commit + reply +
resolve), reject unreasonable ones (reply + resolve), handle CI failures, and
re-request Copilot review when needed. Exit smartly when no more substantive
feedback remains.

## Architecture

State machine with persisted state, driven by `gh` CLI for all GitHub
operations. Project-independent — installed at user level, works in any repo
by reading `AGENTS.md` for conventions.

### States

```
INIT → COLLECT → EVALUATE → IMPLEMENT → WAIT_CI → RE_REQUEST → COLLECT
                                                          ↓
                                                        DONE
```

| State | Purpose |
|-------|---------|
| INIT | Discover PR from git remote, load/create state file |
| COLLECT | Poll PR for new Copilot review comments |
| EVALUATE | Claude judges each unhandled comment |
| IMPLEMENT | Apply code changes, commit, reply, resolve |
| WAIT_CI | Wait for CI to pass; fix failures if needed |
| RE_REQUEST | Dismiss Copilot review and re-request |
| DONE | All comments resolved, smart exit triggered |

### State File

Located at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json` — outside
any git working tree.

```jsonc
{
  "prNumber": 123,
  "owner": "org",
  "repo": "repo",
  "currentState": "COLLECT",
  "round": 2,
  "lastReviewId": 456,
  "handledComments": {
    "12345": { "action": "accepted", "commitSha": "abc" },
    "12346": { "action": "rejected", "reason": "YAGNI - no callers", "topic": "error handling" }
  },
  "roundSummaries": [
    { "round": 1, "accepted": 3, "rejected": 1 }
  ],
  "ciStatus": "passing",
  "smartExit": {
    "consecutiveNoAction": 0
  }
}
```

## Detection: Polling

`gh api /repos/{owner}/{repo}/pulls/{pr}/reviews` filtered to Copilot (GitHub
App login or `author_association` heuristics). New reviews since `lastReviewId`
trigger comment collection. No webhook dependency.

## Comment Evaluation

Each unhandled comment is fed to Claude with surrounding code and project
conventions. Claude returns a structured decision:

- **decision**: accept | reject
- **severity**: critical | important | minor
- **confidence**: high | medium | low
- **reasoning**: technical explanation
- **replyText**: what to post on GitHub

Decision rules (from `receiving-code-review` principles):

| Condition | Action |
|-----------|--------|
| confidence = "low" | Auto-reject, reply, resolve |
| Same file:line + same topic as prior rejection | Auto-reject, cite previous reasoning |
| severity = "minor" + round >= 3 | Auto-reject (diminishing returns) |
| severity = "critical" | Accept regardless of confidence |
| decision = "reject" | Reply with technical reasoning, resolve |

## Implementation

One commit per accepted comment:

1. Apply code change
2. Run lint (`pnpm --filter <package> lint` or equivalent)
3. Commit with `fix(scope): <description>` referencing the review comment URL
4. Reply to GitHub comment thread
5. Resolve conversation
6. Push

Sequential for same-file comments to avoid conflicts.

## CI Gate

1. `gh pr checks` — if failing, read logs, fix, commit, push, re-check
2. Once green, compare CI-fix files with Copilot-commented files
3. Overlap → transition to RE_REQUEST (review is stale)
4. No overlap → transition to COLLECT

## Smart Exit

Checked after each COLLECT:

- `consecutiveNoAction >= 2` — Copilot has nothing new
- All comments minor + round >= 3 — diminishing returns
- Copilot repeats a previously rejected suggestion (same file:line + topic)

Any trigger → DONE, write summary to state file.

## Multi-Agent Compatibility

The skill is agent-agnostic. Canonical logic in `SKILL.md` uses `gh` CLI only.
Thin adapters for each agent map tool names:

```
copilot-review/
├── SKILL.md                 # Canonical, agent-agnostic
├── references/
│   ├── github-api.md        # gh CLI patterns for review operations
│   └── evaluation-prompt.md # Claude prompt for comment evaluation
├── adapters/
│   ├── claude.md
│   ├── copilot.md
│   ├── codex.md
│   └── gemini.md
└── docs/
    └── 2026-05-24-copilot-review-design.md
```

## Key GitHub APIs

| Operation | API |
|-----------|-----|
| List reviews | `GET /repos/{owner}/{repo}/pulls/{pr}/reviews` |
| List review comments | `GET /repos/{owner}/{repo}/pulls/{pr}/comments` |
| Dismiss review | `PUT /repos/{owner}/{repo}/pulls/{pr}/reviews/{id}/dismissals` |
| Request reviewers | `POST /repos/{owner}/{repo}/pulls/{pr}/requested_reviewers` |
| Reply to comment | `POST /repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies` |
| Resolve thread | `PATCH /repos/{owner}/{repo}/pulls/{pr}/comments/{id}` |
| Check CI | `gh pr checks` |

## Out of Scope

- Webhook-based detection (no infra dependency)
- Multi-PR concurrent management (one PR per state file, run multiple sessions for multiple PRs)
- Automatic PR creation (user creates the PR and assigns Copilot, then invokes the skill)

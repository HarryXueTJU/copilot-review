# copilot-review v2: Robustness Improvements

2026-05-25 | Status: Design

## Motivation

Live-testing on `TheDeltaLab/trinity#1538` surfaced three gaps:

1. **RE_REQUEST is broken** — `copilot-pull-request-reviewer` is an Organization type. REST (`/requested_reviewers`) requires collaborators. GraphQL (`requestReviews`) requires User nodes. Both fail. The only reliable trigger is a PR comment `@copilot`.
2. **No merge conflict handling** — The branch fell behind main during the loop. Conflicts block merging and waste Copilot's review context.
3. **Excessive permission prompts** — Every `gh`, `git`, `pnpm` invocation triggers an approval dialog, interrupting the loop's flow.
4. **Copilot replies via issue comments** — When triggered by `@copilot`, Copilot responds as an issue comment, not a review comment. The COLLECT state only scanned review comments.

## Changes

### 1. RE_REQUEST: Replace broken API calls with `@copilot` comment

**Before (broken):**

```bash
# REST → 422 (not a collaborator)
gh api .../requested_reviewers -f "reviewers[]=copilot-pull-request-reviewer"
# GraphQL fallback → "Could not resolve to User node"
```

**After:**

```bash
gh pr edit {pr} --add-assignee "@copilot"
gh pr comment {pr} --body "@copilot"
```

No qualifiers in the comment body — `@copilot` alone triggers a full PR re-review. Adding framing like "review commit X" risks scoping Copilot to a partial diff.

### 2. Conflict detection: Add check at COLLECT entry

Conflicts can arise at any time (other PRs merge, main evolves), not just from our push. Check at the start of every COLLECT cycle so the PR is always mergeable before Copilot reviews it.

If `gh pr view --json mergeable` returns `"CONFLICTING"`:

1. `git fetch origin main && git merge origin/main`
2. Read conflicted files, resolve (keep both changes where possible)
3. `git add <files> && git commit -m "chore: merge main, resolve conflicts" && git push`
4. Re-check mergeable; loop until clean or 3 attempts exhausted
5. If still conflicting after 3 attempts, pause loop and report to user

New state fields: `conflictAttempts` (int), `conflictFiles` (array).

### 3. COLLECT: Also scan issue comments

**Before:** Only scanned `/pulls/{pr}/comments` (review comments).

**After:** Also scan `/issues/{pr}/comments` for Copilot-authored comments.

Both sources filtered by `user.login == "Copilot"` and cross-referenced with `handledComments`. Review comments take priority (they carry file:line context); issue comments supplement.

### 4. Permissions: Allowlist gh/git/pnpm

In `.claude/settings.json`:

```json
{
  "permissions": {
    "Bash": {
      "allow": ["gh *", "git *", "pnpm *", "jq *"]
    },
    "Edit": { "ask": true },
    "Write": { "ask": true }
  }
}
```

All `gh`/`git`/`pnpm`/`jq` commands auto-execute. Only code edits (Edit/Write) require confirmation — the one step that benefits from human oversight.

### 5. Updated state machine

```
COLLECT ──(mergeable?)──> [resolve conflicts if needed]
    │
    ▼
EVALUATE ──(any accepted?)──> IMPLEMENT ──> WAIT_CI ──> RE_REQUEST
    │                                                         │
    └──(all rejected)──> COLLECT ◄────────────────────────────┘
```

No new `CHECK_CONFLICT` state — the check lives at COLLECT entry to catch conflicts regardless of origin.

### 6. Updated github-api.md

- Remove broken REST/GraphQL reviewer request recipes
- Document `gh pr edit --add-assignee "@copilot"` for assignment
- Document `gh pr comment --body "@copilot"` as the re-review trigger
- Add conflict check recipe: `gh pr view --json mergeable,mergeStateStatus`
- Add issue comment listing recipe

## State File Schema

Add to existing schema:

```json
{
  "conflictAttempts": 0,
  "conflictFiles": [],
  "permissionsConfigured": false
}
```

## Migration

Existing state files remain compatible. Missing fields default to zero/false.

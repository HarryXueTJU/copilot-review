# copilot-review Robustness Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix RE_REQUEST, add merge conflict handling, scan issue comments, and pre-authorize gh/git/pnpm to reduce permission prompts.

**Architecture:** Four focused edits to SKILL.md (state machine + COLLECT + RE_REQUEST + state schema) and one reference doc update (github-api.md). One new file (`.claude/settings.json`). No new states — conflict check folds into COLLECT entry.

**Tech Stack:** Bash, jq, gh CLI, git, JSON state files

**Spec:** `docs/superpowers/specs/2026-05-25-copilot-review-robustness-design.md`

---

### Task 1: Update RE_REQUEST state to use `@copilot` comment

**Files:**
- Modify: `SKILL.md` (RE_REQUEST section, lines 220-238)

**Context:** The old RE_REQUEST used REST `/requested_reviewers` + GraphQL fallback — both broken because `copilot-pull-request-reviewer` is an Organization type. The new approach: assign Copilot via `--add-assignee` and trigger review via a `@copilot` PR comment with no qualifiers.

- [ ] **Step 1: Replace RE_REQUEST state content**

Replace the entire RE_REQUEST section (lines 220-238) in SKILL.md:

```markdown
### State: RE_REQUEST

1. **Assign Copilot to the PR:**
   ```bash
   gh pr edit {pr} --repo {owner}/{repo} --add-assignee "@copilot"
   ```
   This ensures Copilot appears as assigned in the PR sidebar (UI parity).

2. **Trigger Copilot re-review via comment:**
   ```bash
   gh pr comment {pr} --repo {owner}/{repo} --body "@copilot"
   ```
   No qualifiers — `@copilot` alone triggers a full PR re-review. Adding framing
   like "review commit X" risks scoping Copilot to a partial diff. `@copilot`'s
   default behavior is to review all changes on the PR.

   Note: This creates an issue comment, not a review comment. The COLLECT state
   scans both sources (see COLLECT state updates).

3. **Update state:** increment round, save round summary, clear `ciFixFiles`,
   reset `ciAttempts` to 0, reset `lastReviewId` to null, reset
   `consecutiveNoAction` to 0. Save state file.

4. **Transition to COLLECT.**
```

- [ ] **Step 2: Verify the edit is consistent**

Check that no other section references the old REST/GraphQL re-request flow.

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "fix: replace broken RE_REQUEST APIs with @copilot comment trigger"
```

---

### Task 2: Add merge conflict check at COLLECT entry

**Files:**
- Modify: `SKILL.md` (COLLECT section, lines 92-122)

**Context:** Conflicts can arise from other PRs merging, not just our push. Check at COLLECT entry so the PR is always mergeable before Copilot reviews.

- [ ] **Step 1: Insert conflict check at start of COLLECT**

Replace the COLLECT section (lines 92-122) with updated content that adds a step 0 before the existing review-fetching steps:

```markdown
### State: COLLECT

0. **Check for merge conflicts.** Conflicts can arise at any time (other PRs
   merge, main evolves). Ensure the PR is mergeable before Copilot reviews it.

   ```bash
   mergeable=$(gh pr view {pr} --repo {owner}/{repo} --json mergeable --jq '.mergeable')
   ```

   If `mergeable` is `"CONFLICTING"`:
   - `git fetch origin {base}` (base branch from state file or PR metadata)
   - `git merge origin/{base}` — this produces conflict markers in affected files
   - Read each conflicted file, resolve by keeping both changes where possible.
     When two branches independently add different blocks (non-overlapping), keep
     both. When the same lines differ, prefer `origin/{base}` structure and add
     our changes on top.
   - `git add <conflicted files>`
   - `git commit -m "chore: merge {base}, resolve conflicts"`
   - `git push`
   - Increment `conflictAttempts` in state file.
   - If `conflictAttempts >= 3`: report unresolvable conflict to user and
     pause the loop (set state to DONE with exit reason "unresolvable conflict").
   - Re-check `mergeable`. If still `"CONFLICTING"`, loop back to the merge step.

   If `mergeable` is `null` or `"UNKNOWN"`: the merge check hasn't completed
   yet. Wait 10 seconds and re-check, up to 5 times.

   Once `mergeable` is `"MERGEABLE"`, reset `conflictAttempts` to 0 and proceed.

1. **Fetch Copilot reviews.**
   ... (existing steps 1-7 continue unchanged)
```

- [ ] **Step 2: Add conflict fields to INIT state schema**

In the INIT section (around line 77), add to the state JSON:

```json
"conflictAttempts": 0,
"conflictFiles": []
```

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat: add merge conflict detection and resolution at COLLECT entry"
```

---

### Task 3: Add issue comment scanning to COLLECT

**Files:**
- Modify: `SKILL.md` (COLLECT section, step 4 area)

**Context:** When triggered via `@copilot`, Copilot responds as an issue comment (not a review comment). COLLECT must scan both sources.

- [ ] **Step 1: Add issue comment fetch after the existing review comment fetch**

After step 4 (existing review comment fetch), add a new step for issue comments:

```markdown
5. **Also fetch Copilot issue comments** (needed because `@copilot` mentions
   trigger issue-comment responses, not review comments):

   ```bash
   gh api "/repos/{owner}/{repo}/issues/{pr}/comments?per_page=100" \
     --jq '.[] | select(.user.login == "Copilot" and .in_reply_to_id == null) | {id, body, created_at}'
   ```

   Merge with the review-comment list from step 4. Review comments carry
   `path` and `line` context and take priority during evaluation. Issue
   comments supplement — when an issue comment references a file path in its
   body, extract that context for the EVALUATE phase.
```

- [ ] **Step 2: Renumber existing steps 5-7 to 6-8**

- [ ] **Step 3: Commit**

```bash
git add SKILL.md
git commit -m "feat: scan issue comments in COLLECT for @copilot-triggered responses"
```

---

### Task 4: Update github-api.md reference

**Files:**
- Modify: `references/github-api.md`

- [ ] **Step 1: Remove broken review-request sections**

Remove the "Dismiss a Review" section entirely (COMMENTED reviews can't be dismissed — Copilot's default).

Remove the "Re-request Reviewers" section (both REST and GraphQL approaches are broken).

- [ ] **Step 2: Add new recipes**

Add after the "Get PR Node ID" section:

```markdown
## Request Copilot Review (Re-request)

Assign Copilot to the PR and trigger a re-review:

```bash
# Assign Copilot (makes it visible in PR sidebar)
gh pr edit {pr} --repo {owner}/{repo} --add-assignee "@copilot"

# Trigger review via @copilot mention (no qualifiers — reviews full PR)
gh pr comment {pr} --repo {owner}/{repo} --body "@copilot"
```

## Check for Merge Conflicts

```bash
gh pr view {pr} --repo {owner}/{repo} --json mergeable,mergeStateStatus --jq '{mergeable, status: .mergeStateStatus}'
```

If `mergeable` is `"CONFLICTING"`:
- `git fetch origin main && git merge origin/main`
- Resolve conflict markers, commit, push
- Re-check until `"MERGEABLE"`
- If still `"CONFLICTING"` after 3 attempts, report to user

## List Issue Comments (for Copilot responses)

Copilot often responds to `@copilot` mentions as issue comments, not review
comments. Fetch both:

```bash
gh api "/repos/{owner}/{repo}/issues/{pr}/comments?per_page=100" \
  --jq '.[] | select(.user.login == "Copilot" and .in_reply_to_id == null) | {id, body, created_at}'
```

Filter: `user.login == "Copilot"` and `in_reply_to_id == null` (top-level only).
```

- [ ] **Step 3: Commit**

```bash
git add references/github-api.md
git commit -m "docs: update github-api reference with working Copilot trigger and conflict recipes"
```

---

### Task 5: Create .claude/settings.json for permissions

**Files:**
- Create: `.claude/settings.json`

- [ ] **Step 1: Create the settings file**

```json
{
  "permissions": {
    "Bash": {
      "allow": [
        "gh *",
        "git *",
        "pnpm *",
        "npm *",
        "yarn *",
        "jq *"
      ]
    },
    "Edit": {
      "ask": true
    },
    "Write": {
      "ask": true
    }
  }
}
```

- [ ] **Step 2: Verify settings file is valid JSON**

```bash
jq . .claude/settings.json
```

- [ ] **Step 3: Commit**

```bash
git add .claude/settings.json
git commit -m "chore: pre-authorize gh/git/pnpm in permissions allowlist"
```

---

### Task 6: Update state file schema documentation

**Files:**
- Modify: `SKILL.md` (INIT section, state JSON)

**This was already partially done in Task 2 Step 2.** Verify the INIT state JSON includes all new fields:

```json
{
  "prNumber": <n>,
  "owner": "<o>",
  "repo": "<r>",
  "currentState": "COLLECT",
  "round": 0,
  "lastReviewId": null,
  "handledComments": {},
  "roundSummaries": [],
  "ciStatus": "unknown",
  "ciAttempts": 0,
  "ciFixFiles": [],
  "conflictAttempts": 0,
  "conflictFiles": [],
  "smartExit": { "consecutiveNoAction": 0 }
}
```

- [ ] **Step 1: Verify fields are all present**

Read the INIT section and confirm `conflictAttempts` and `conflictFiles` are in the JSON schema.

- [ ] **Step 2: If missing, fix**

- [ ] **Step 3: Commit only if changes were needed**

```bash
git add SKILL.md
git commit -m "chore: ensure state schema includes conflict tracking fields"
```

---

### Task 7: Final review — cross-reference consistency

**Files:**
- Read: `SKILL.md`
- Read: `references/github-api.md`

- [ ] **Step 1: Verify no section references the old REST/GraphQL re-request**

```bash
grep -n "requested_reviewers\|requestReviews\|dismissals" SKILL.md references/github-api.md
```
Should return no output (or only in explanatory context like "old approach was broken").

- [ ] **Step 2: Verify state transitions are consistent**

COLLECT → EVALUATE → IMPLEMENT → WAIT_CI → RE_REQUEST → COLLECT.
No new states. Conflict check at COLLECT entry, not a separate state.

- [ ] **Step 3: Verify COLLECT scans both comment types**

```bash
grep -n "issues.*comments\|review.*comments" SKILL.md
```
Should show both `/issues/{pr}/comments` and `/pulls/{pr}/comments`.

- [ ] **Step 4: Commit if any fixes were needed**

```bash
git add SKILL.md references/github-api.md
git commit -m "chore: cross-reference consistency fixes"
```

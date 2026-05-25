---
name: copilot-review
description: Automate the GitHub Copilot PR review feedback loop — collect reviews, evaluate comments, implement accepted changes, handle CI, re-request review, exit smartly.
argument-hint: "<pr-number> | status | resume | stop"
---

# /copilot-review — Automated Copilot PR Review Loop

State-machine-driven skill. One state file per PR at
`.claude/copilot-review/<owner>-<repo>-<prNumber>.json`. All GitHub operations
use `gh` CLI.

Read `references/github-api.md` for exact `gh` command recipes.
Read `references/evaluation-prompt.md` for comment evaluation instructions.

## Prerequisites

These must be available and working before starting:

| Tool | Check | Required For |
|------|-------|-------------|
| `gh` CLI | `gh auth status` | All GitHub API operations |
| `git` | `git --version` | Committing changes, discovering PR |
| `jq` | `jq --version` | Parsing API responses and state files |

**gh auth scopes needed:** `pull-requests: read` (view reviews/comments),
`pull-requests: write` (dismiss/re-request/reply), `actions: read` (CI checks).

Run these checks before entering the state machine. If any tool is missing,
report which one and how to install it, then stop.

## Sub-commands

| Command | Description |
|---------|-------------|
| `/copilot-review <pr-number>` | Start or resume the review loop for a PR |
| `/copilot-review status` | Show current state and round summary |
| `/copilot-review resume` | Resume from the last saved state |
| `/copilot-review stop` | Write DONE to state file and exit |

---

## State Machine

```
INIT → COLLECT → EVALUATE → IMPLEMENT → WAIT_CI → RE_REQUEST → COLLECT
                                                          ↓
                                                        DONE
```

### State: INIT

0. **Check prerequisites.** Verify required tools exist:
   ```bash
   gh auth status 2>&1 || { echo "gh CLI not authenticated. Run: gh auth login"; exit 1; }
   git --version 2>&1 || { echo "git not found."; exit 1; }
   jq --version 2>&1 || { echo "jq not found. Install: brew install jq"; exit 1; }
   ```
   If any check fails, report the missing tool and stop. Do not proceed.

1. **Determine PR.** If `<pr-number>` was passed, use it. Otherwise discover from git:
   ```bash
   owner=$(git remote get-url origin | sed 's|.*[:/]\([^/]*\)/\([^/.]*\).*|\1|')
   repo=$(git remote get-url origin | sed 's|.*[:/][^/]*/\([^/.]*\).*|\1|')
   ```
   If the current branch has an open PR via
   `gh pr list --head <branch> --json number --jq '.[0].number'`, use that.
   Otherwise prompt the user for the PR number.

2. **Load or create state file.**
   Path: `.claude/copilot-review/${owner}-${repo}-${prNumber}.json`
   If it exists, read it. If not, create with:
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

3. **Transition to COLLECT.**

### State: COLLECT

0. **Check for merge conflicts.** Conflicts can arise at any time (other PRs
   merge, main evolves). Ensure the PR is mergeable before Copilot reviews it.

   ```bash
   gh pr view {pr} --repo {owner}/{repo} --json mergeable,baseRefName \
     --jq '{mergeable, base: .baseRefName}'
   ```

   If `mergeable` is `"CONFLICTING"`:
   - Resolve `{base}` from the command output above.
   - `git stash` (if there are uncommitted changes from an interrupted IMPLEMENT)
   - `git fetch origin {base}`
   - `git merge origin/{base}` — this produces conflict markers in affected files
   - Read each conflicted file. When two branches independently add different
     blocks (non-overlapping), keep both. When the same lines differ, prefer
     `origin/{base}` structure and add our changes on top.
   - `git add <conflicted files>`
   - `git commit -m "chore: merge {base}, resolve conflicts"`
   - `git push`
   - Increment `conflictAttempts` in state file. Append file names to
     `conflictFiles`.
   - If `conflictAttempts >= 3`: report unresolvable conflict to user and
     pause the loop (transition to DONE with exit reason
     `"unresolvable conflict"`).
   - Wait 15 seconds for GitHub to re-evaluate mergeability, then re-check
     `mergeable`. If still `"CONFLICTING"`, loop back to the merge step.

   If `mergeable` is `null` or `"UNKNOWN"`: the merge check hasn't completed
   yet. Wait 10 seconds and re-check, up to 5 times. If still unresolved after
   5 attempts, transition to DONE with exit reason `"merge check timeout"`.

   Once `mergeable` is `"MERGEABLE"`, reset `conflictAttempts` to 0 and proceed.

1. **Fetch Copilot reviews.**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews?per_page=100" \
     --jq '.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {id, submitted_at}'
   ```

2. **Filter to new reviews** (id > `lastReviewId` from state file, or all if
   `lastReviewId` is null).

3. **For each new review, fetch Copilot review comments:**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/comments?per_page=100" \
     --jq '.[] | select(.pull_request_review_id == {review_id} and .user.login == "Copilot" and .in_reply_to_id == null) | {id, body, path, line, diff_hunk}'
   ```

4. **Fetch Copilot issue comments** (always — Copilot may respond via issue
   comments even when no review object exists):

   ```bash
   gh api "/repos/{owner}/{repo}/issues/{pr}/comments?per_page=100" \
     --jq '.[] | select(.user.login == "Copilot" and .in_reply_to_id == null) | {id, body, created_at}'
   ```

5. **Merge both comment sources.** Review comments carry `path` and `line`
   context and take priority during evaluation. When an issue comment
   references a file path in its body, extract that context for EVALUATE.
   Cross-reference both sources with `handledComments` — skip
   already-handled IDs. Copy new comments to a working list.

6. **If unhandled comments exist:** save them to a working list, update
   `lastReviewId` to the latest review ID, transition to EVALUATE.

7. **If no unhandled comments and `round == 0`:**
   No Copilot review has been triggered yet. Transition to RE_REQUEST to
   post the initial `@copilot review this PR` comment.

8. **If no unhandled comments and `round > 0`:**
   - Increment `consecutiveNoAction` in state.
   - **Smart exit check:** If `consecutiveNoAction >= 2`, transition to DONE.
   - Otherwise: wait 30 seconds, then re-enter COLLECT (go to step 0).

### State: EVALUATE

For each unhandled comment, evaluate independently:

1. **Gather context:**
   - Read the source file at `{path}` around `{line}` (20 lines of context)
   - Read the nearest `AGENTS.md` by walking up from the file's directory
   - Collect `priorRejections` from `handledComments` where `action == "rejected"`
   - Get current `round` from state file

2. **Evaluate** using the prompt template in `references/evaluation-prompt.md`.
   Feed: comment body, file path, line, diff hunk, round, prior rejections.

3. **Classify each comment** based on the decision:
   - **Accepted** → queue for IMPLEMENT
   - **Rejected** → reply to GitHub thread, resolve, record in `handledComments`

4. **After all evaluations:**
   - If any accepted → transition to IMPLEMENT
   - If all rejected → record round summary in state, increment
     `consecutiveNoAction`, transition to COLLECT

### State: IMPLEMENT

For each accepted comment, process sequentially (same-file comments must be
ordered to avoid conflicts):

1. **Apply the code change.** Edit the file based on the comment's suggestion
   and the evaluation's reasoning.

2. **Run lint.** Detect the project's linter:
   ```bash
   pnpm --filter <package> lint 2>/dev/null || npm run lint 2>/dev/null || yarn lint 2>/dev/null
   ```
   If lint fails and the failure is from this change, fix it. If lint fails
   from pre-existing issues, note it and continue.

3. **Commit.**
   ```bash
   git add <changed files>
   git commit -m "fix(<scope>): <brief description>

   Addresses: https://github.com/{owner}/{repo}/pull/{pr}#discussion_r{comment_id}"
   ```

4. **Push.**
   ```bash
   git push
   ```

5. **Reply to GitHub thread** using the `replyText` from evaluation:
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/comments" \
     --method POST \
     -f body="<replyText>" \
     -f in_reply_to="{comment_id}"
   ```

6. **Record in state:** Add entry to `handledComments` with `action: "accepted"`,
   `commitSha` (from the commit), file, line, decision, severity, confidence.

7. **If more accepted comments remain:** go to step 1 with next comment.

8. **All done:** Record round summary, transition to WAIT_CI.

### State: WAIT_CI

1. **Wait for CI to start.** After push, wait 30 seconds for GitHub Actions
   to pick up the new commit.

2. **Check CI status** (poll every 30s until all checks complete):
   ```bash
   gh pr checks {pr} --json name,state --jq '.[] | select(.state != "SUCCESS" and .state != "SKIPPED" and .state != "NEUTRAL") | {name, state}'
   ```
   If any check is still `"PENDING"` or `"IN_PROGRESS"`, wait 30s and re-check.
   If all checks are `"SUCCESS"`, `"SKIPPED"`, or `"NEUTRAL"` → CI is green.

3. **If any check is failing** (max 3 fix attempts):
   - Get the failing workflow run ID:
     ```bash
     gh pr checks {pr} --json name,state,detailsUrl --jq '.[] | select(.state == "FAILURE")'
     ```
   - Read logs: `gh run view <run_id_from_url> --log 2>&1 | tail -100`
   - Analyze failure and attempt to fix.
   - If fixable (and `ciAttempts < 3`): edit files, lint, commit with
     `ci(scope): fix <check name>`, push, increment `ciAttempts`, append
     fixed files to `ciFixFiles`, go back to step 1.
   - If `ciAttempts >= 3` or not fixable (flaky test, infra issue): report
     to user and pause the loop.

4. **Once CI is green:**
   - **Always transition to RE_REQUEST** — Copilot must be explicitly
     re-requested to review the new commits. The `ciFixFiles` overlap check
     determines whether to add a note about stale review context but does not
     skip the re-request.

### State: RE_REQUEST

1. **Get PR node ID:**
   ```bash
   prId=$(gh pr view {pr} --repo {owner}/{repo} --json id --jq '.id')
   ```

2. **Request Copilot review via GraphQL:**
   ```bash
   gh api graphql --raw-field 'query=mutation($prId: ID!) {
     requestReviewsByLogin(input: {
       pullRequestId: $prId,
       botLogins: ["copilot-pull-request-reviewer[bot]"]
     }) { pullRequest { url } }
   }' -f prId="$prId"
   ```
   This is the same GraphQL mutation the GitHub UI uses when clicking
   "Request Copilot review". The `botLogins` field accepts Copilot's login
   with the `[bot]` suffix — this is the key difference from the standard
   `requestReviews` mutation which only accepts User nodes.

3. **If GraphQL fails,** fall back to a PR comment:
   ```bash
   gh pr comment {pr} --repo {owner}/{repo} --body "@copilot review this PR"
   ```

4. **Update state:** increment round, save round summary, clear `ciFixFiles`,
   reset `ciAttempts` to 0, reset `lastReviewId` to null, reset
   `consecutiveNoAction` to 0. Save state file.

5. **Transition to COLLECT.**

### State: DONE

1. **Write final summary** to state file with exit reason.

2. **Print summary to user:**
   ```
   Copilot review loop complete.
   PR: https://github.com/{owner}/{repo}/pull/{pr}
   Rounds: {n}
   Total accepted: {accepted_count}
   Total rejected: {rejected_count}
   Exit reason: {reason}
   ```

3. **Stop.** No further transitions.

---

## Smart Exit Conditions

Checked after every COLLECT with no new actionable comments:

1. **`consecutiveNoAction >= 2`** — Two rounds with no accepted comments.
   Copilot has no more substantive feedback.

2. **All comments minor + round >= 3** — After 3 rounds, only minor/style
   comments remain. Diminishing returns; stop.

3. **Repeat detection** — A new Copilot comment matches the same
   `file + line + topic` as a previously rejected comment. Copilot is
   repeating itself.

When any trigger fires, write the exit reason to state and transition to DONE.

---

## Sub-command: `status`

Read the state file and print a summary:

```bash
cat .claude/copilot-review/${owner}-${repo}-${prNumber}.json | jq '{
  pr: "#\(.prNumber)",
  state: .currentState,
  round: .round,
  handled: (.handledComments | length),
  accepted: [.handledComments[] | select(.action == "accepted")] | length,
  rejected: [.handledComments[] | select(.action == "rejected")] | length,
  ci: .ciStatus
}'
```

## Sub-command: `resume`

Read the state file. If `currentState` is one of the valid states
(`COLLECT`, `EVALUATE`, `IMPLEMENT`, `WAIT_CI`, `RE_REQUEST`),
begin execution from that state. Otherwise (unknown state, `DONE`, or `INIT`),
start from INIT.

## Sub-command: `stop`

Set `currentState` to `"DONE"` in the state file, write an exit reason of
`"manual stop"`, and exit.

---

## Error Recovery

- If a step fails (network error, API rate limit, merge conflict), save state
  and stop. State file preserves progress.
- Resume with `/copilot-review resume` after fixing the underlying issue.
- If CI fix introduces new failures, record the attempt and try up to 3 times
  before asking the user.
- If `gh` is not authenticated, report and stop.

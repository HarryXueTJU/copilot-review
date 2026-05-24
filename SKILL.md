---
name: copilot-review
description: Automate the GitHub Copilot PR review feedback loop — collect reviews, evaluate comments, implement accepted changes, handle CI, re-request review, exit smartly.
argument-hint: "<pr-number> | status | resume | stop"
---

# /copilot-review — Automated Copilot PR Review Loop

State-machine-driven skill. One state file per PR at
`~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`. All GitHub operations
use `gh` CLI.

Read `references/github-api.md` for exact `gh` command recipes.
Read `references/evaluation-prompt.md` for comment evaluation instructions.

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

1. **Determine PR.** If `<pr-number>` was passed, use it. Otherwise discover from git:
   ```bash
   owner=$(git remote get-url origin | sed 's|.*[:/]\([^/]*\)/\([^/.]*\).*|\1|')
   repo=$(git remote get-url origin | sed 's|.*[:/][^/]*/\([^/.]*\).*|\1|')
   ```
   If the current branch has an open PR via
   `gh pr list --head <branch> --json number --jq '.[0].number'`, use that.
   Otherwise prompt the user for the PR number.

2. **Load or create state file.**
   Path: `~/.claude/copilot-review/${owner}-${repo}-${prNumber}.json`
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
     "ciFixFiles": [],
     "smartExit": { "consecutiveNoAction": 0 }
   }
   ```

3. **Transition to COLLECT.**

### State: COLLECT

1. **Fetch Copilot reviews.**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews?per_page=100" \
     --jq '.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {id, submitted_at}'
   ```

2. **Filter to new reviews** (id > `lastReviewId` from state file, or all if
   `lastReviewId` is null).

3. **If no new reviews:**
   - Increment `consecutiveNoAction` in state.
   - **Smart exit check:** If `consecutiveNoAction >= 2`, transition to DONE.
   - Otherwise: wait 120 seconds, then re-enter COLLECT (go to step 1).

4. **For each new review, fetch Copilot comments:**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/comments?per_page=100" \
     --jq '.[] | select(.pull_request_review_id == {review_id} and .user.login == "Copilot" and .in_reply_to_id == null) | {id, body, path, line, diff_hunk}'
   ```

5. **Cross-reference with `handledComments`** — skip already-handled IDs.
   Copy any new comments to a working list for EVALUATE.

6. **If no unhandled comments found in any new review:**
   update `lastReviewId` to the latest review ID, increment
   `consecutiveNoAction`, do smart exit check, wait and re-enter COLLECT.

7. **If unhandled comments exist:** save them to a working list, update
   `lastReviewId` to the latest review ID, transition to EVALUATE.

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

1. **Check CI status:**
   ```bash
   gh pr checks {pr} | grep -v 'pass\t' | grep -v 'skipped\t' | grep -v 'neutral\t'
   ```

2. **If any check is failing:**
   - Read the failing check logs via `gh run view <run_id> --log`
   - Analyze the failure from the log output
   - If fixable: edit files, lint, commit with `ci(scope): fix <check name>`,
     push, append fixed files to `ciFixFiles` in state
   - Go back to step 1 (re-check CI)
   - If not fixable (flaky test, infra issue): report to user, pause the loop

3. **Once CI is green:**
   - Compare `ciFixFiles` with file paths in `handledComments` where
     `action == "accepted"`
   - **If overlap** (any CI-fixed file matches a commented file) →
     transition to RE_REQUEST
   - **If no overlap** → transition to COLLECT

### State: RE_REQUEST

1. **Re-request Copilot review:**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/requested_reviewers" \
     --method POST \
     -f "reviewers[]=copilot-pull-request-reviewer"
   ```
   Note: COMMENTED reviews cannot be dismissed. Skip dismissal, just re-request.

2. **Update state:** increment round, save round summary, clear `ciFixFiles`,
   reset `lastReviewId` to null, reset `consecutiveNoAction` to 0.

3. **Transition to COLLECT.**

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
cat ~/.claude/copilot-review/${owner}-${repo}-${prNumber}.json | jq '{
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

Read the state file. If `currentState` is valid, begin execution from that
state. Otherwise, start from INIT.

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

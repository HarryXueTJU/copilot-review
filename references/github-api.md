# GitHub API Reference for Copilot Review Skill

All commands use `gh api` with `--jq` for field extraction. Replace `{owner}`, `{repo}`, `{pr}` with actual values.

**Required token permissions:** `pull-requests: read` (view reviews/comments), `pull-requests: write` (dismiss/re-request/reply), `actions: read` (CI checks).

**Pagination:** Use `--paginate` on list endpoints to handle more than 100 items. Omitted from examples below for brevity but should be used in automation.

## Copilot Identity

| Role | Login |
|------|-------|
| Review author | `copilot-pull-request-reviewer[bot]` |
| Comment author | `Copilot` |

## List Reviews

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews?per_page=100" \
  --jq '.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {id, state, submitted_at}'
```

Key fields: `id` (review ID), `state` (COMMENTED, APPROVED, etc.), `submitted_at`

## List Review Comments

Get all review comments on the PR:

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/comments?per_page=100" \
  --jq '.[] | {id, user: .user.login, body, path, line, diff_hunk, in_reply_to_id, pull_request_review_id, subject_type}'
```

Key fields: `id`, `user.login`, `body`, `path`, `line`, `diff_hunk`, `pull_request_review_id`, `in_reply_to_id`

Filter to Copilot comments:
```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/comments?per_page=100" \
  --jq '.[] | select(.user.login == "Copilot" and .in_reply_to_id == null) | {id, body, path, line, diff_hunk, pull_request_review_id}'
```

`in_reply_to_id == null` ensures we get only top-level comments (not replies in threads).

## Get Comments for a Specific Review

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/comments?per_page=100" \
  --jq '.[] | select(.pull_request_review_id == {review_id} and .user.login == "Copilot") | {id, body, path, line, diff_hunk}'
```

## Reply to a Review Comment

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/comments" \
  --method POST \
  -f body="Reply text here" \
  -f in_reply_to="{comment_id}"
```

The API endpoint for replying is `POST /repos/{owner}/{repo}/pulls/{pr}/comments` with `in_reply_to` set to the parent comment ID. This creates a reply in the thread.

## Resolve a Review Thread

GitHub REST API does not support resolving review threads. Use GraphQL.

First, find the thread node ID for a given comment:

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!, $commentId: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          id
          comments(first: 1) {
            nodes { databaseId }
          }
        }
      }
    }
  }
}' -f owner="{owner}" -f repo="{repo}" -f pr={pr} -f commentId={comment_id} \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.comments.nodes[0].databaseId == {comment_id}) | .id'
```

Then resolve the thread:

```bash
THREAD_ID="<from query above>"
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { isResolved }
  }
}' -f threadId="$THREAD_ID"
```

## Request Copilot Review (Re-request)

Required approach — request Copilot as a reviewer:

```bash
gh pr edit {pr} --repo {owner}/{repo} --add-reviewer @copilot
```

Do not use `@copilot` in a PR comment as a substitute for reviewer assignment.
Comment mentions are not a reliable review trigger.

## Check for Merge Conflicts

```bash
gh pr view {pr} --repo {owner}/{repo} --json mergeable,baseRefName \
  --jq '{mergeable, base: .baseRefName}'
```

Possible `mergeable` values: `"MERGEABLE"` (clean), `"CONFLICTING"` (needs resolution),
`"UNKNOWN"` (still computing), `null` (not yet evaluated).

If `"CONFLICTING"`:
- `git stash && git fetch origin {base} && git merge origin/{base}`
- Resolve conflict markers, commit, push
- Wait 15s for re-evaluation, re-check
- If still conflicting after 3 attempts, report to user

## List Issue Comments (for Copilot responses)

Copilot often responds to `@copilot` mentions as issue comments, not review
comments. Fetch both:

```bash
gh api "/repos/{owner}/{repo}/issues/{pr}/comments?per_page=100" \
  --jq '.[] | select(.user.login == "Copilot" and .in_reply_to_id == null) | {id, body, created_at}'
```

Filter: `user.login == "Copilot"` and `in_reply_to_id == null` (top-level only).

## Check CI Status

Tabular output (parse with grep/awk):
```bash
gh pr checks {pr}
```

Output format (tab-separated): `checkName\tstatus\tduration\turl`

Possible status values: `pass`, `fail`, `pending`, `skipped`, `neutral`, `cancelled`, `timed_out`, `action_required`

Filter to failing checks:
```bash
gh pr checks {pr} | grep -v 'pass\t' | grep -v 'skipped\t' | grep -v 'neutral\t'
```

JSON output (valid fields: `name`, `state`, `bucket`, `completedAt`, `description`, `event`, `link`, `startedAt`, `workflow`):
```bash
gh pr checks {pr} --json name,state --jq '.[] | select(.state != "SUCCESS" and .state != "SKIPPED" and .state != "NEUTRAL") | {name, state}'
```

## Get Check Run Logs

```bash
gh run view <run_id> --log
```

Extract run_id from the check URL (`.../actions/runs/<run_id>/...`).

## Get PR Node ID (for GraphQL)

```bash
gh pr view {pr} --json id --jq '.id'
```

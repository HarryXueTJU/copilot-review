# GitHub API Reference for Copilot Review Skill

All commands use `gh api` with `--jq` for field extraction. Replace `{owner}`, `{repo}`, `{pr}` with actual values.

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

## Dismiss a Review

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews/{review_id}/dismissals" \
  --method PUT \
  -f message="Re-requesting review after changes" \
  -f event="DISMISS"
```

## Re-request Reviewers

To re-add Copilot as a reviewer after dismissal, use the GraphQL API (REST does not support bot re-request):

```bash
gh api graphql -f query='
mutation {
  requestReviews(input: {
    pullRequestId: "<PR_NODE_ID>",
    teamReviewerIds: [],
    userIds: []
  }) {
    pullRequest { url }
  }
}'
```

Note: The PR node ID can be obtained via:
```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) { id }
  }
}' -f owner="{owner}" -f repo="{repo}" -f number={pr}
```

**Alternative:** If the REST API works for re-requesting, use:
```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/requested_reviewers" \
  --method POST \
  -f "reviewers[]=copilot-pull-request-reviewer"
```

Try REST first; fall back to GraphQL if it fails.

## Reply to a Review Comment

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/comments" \
  --method POST \
  -f body="Reply text here" \
  -f in_reply_to="{comment_id}"
```

The API endpoint for replying is `POST /repos/{owner}/{repo}/pulls/{pr}/comments` with `in_reply_to` set to the parent comment ID. This creates a reply in the thread.

## Resolve a Review Thread

GitHub REST API does not directly support resolving review threads. Use GraphQL:

```bash
gh api graphql -f query='
mutation {
  resolveReviewThread(input: {
    threadId: "<THREAD_ID>"
  }) {
    thread { isResolved }
  }
}'
```

The thread ID can be obtained from the comment — it is the `pull_request_review_id` field.

**Alternative approach:** Replying to a thread and resolving can sometimes be combined. The thread is auto-resolved when the last comment includes a resolution hint. If GraphQL is not available, replying with the acceptance outcome and letting the PR author manually resolve is acceptable.

## Check CI Status

```bash
gh pr checks {pr}
```

Output format (tab-separated): `checkName\tstatus\tduration\turl`

Parse status: `pass`, `fail`, `pending`, `skipped`, `neutral`, `cancelled`, `timed_out`, `action_required`

```bash
gh pr checks {pr} --json name,state,conclusion --jq '.[] | select(.conclusion != "SUCCESS" and .conclusion != "SKIPPED" and .conclusion != "NEUTRAL") | {name, conclusion}'
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

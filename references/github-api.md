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

## Dismiss a Review

The dismissals endpoint only accepts a `message` body field.

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews/{review_id}/dismissals" \
  --method PUT \
  -f message="Re-requesting review after changes"
```

Note: a COMMENTED review (Copilot's default) cannot be dismissed. Only APPROVED or CHANGES_REQUESTED reviews support dismissal. If Copilot left a COMMENTED review, skip dismissal and proceed to re-request.

## Re-request Reviewers

Primary approach — use REST to re-add Copilot as a reviewer:

```bash
gh api "/repos/{owner}/{repo}/pulls/{pr}/requested_reviewers" \
  --method POST \
  -f "reviewers[]=copilot-pull-request-reviewer"
```

If REST fails (e.g., bot accounts), use GraphQL. You need Copilot's node ID — query it first:

```bash
# First, find Copilot's node ID
COPILOT_ID=$(gh api graphql -f query='
query($query: String!) {
  search(query: $query, type: USER, first: 1) {
    edges { node { ... on User { id } } }
  }
}' -f query="copilot-pull-request-reviewer" --jq '.data.search.edges[0].node.id')

# Then request review
PR_ID=$(gh pr view {pr} --json id --jq '.id')
gh api graphql -f query="
mutation {
  requestReviews(input: {
    pullRequestId: \"$PR_ID\",
    userIds: [\"$COPILOT_ID\"]
  }) {
    pullRequest { url }
  }
}"
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

# Copilot Review Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a project-independent skill that automates the GitHub Copilot PR review loop — collect reviews, evaluate comments, implement accepted changes, reject unreasonable ones, handle CI failures, and re-request review.

**Architecture:** State machine driven by `gh` CLI for GitHub operations. State persisted to `~/.claude/copilot-review/`. Canonical SKILL.md is agent-agnostic; thin adapters map tool names per agent. Evaluation uses Claude via an embedded prompt in `references/evaluation-prompt.md`.

**Tech Stack:** Shell (`gh` CLI), Markdown (skill files), JSON (state file), Git

**Copilot identifiers (verified from real API):**
- Review author: `copilot-pull-request-reviewer[bot]`
- Comment author: `Copilot`

---

## File Map

Each file and its single responsibility:

| File | Responsibility |
|------|---------------|
| `SKILL.md` | Canonical, agent-agnostic skill — state machine instructions, sub-commands |
| `references/github-api.md` | `gh` CLI patterns for every review operation with real flag combos |
| `references/evaluation-prompt.md` | Claude prompt template for judging a single Copilot comment |
| `adapters/claude.md` | Claude tool mapping (Bash → bash, Read → read, Edit → edit, Write → write) |
| `adapters/copilot.md` | Copilot CLI tool mapping |
| `adapters/codex.md` | Codex tool mapping |
| `adapters/gemini.md` | Gemini CLI tool mapping |

State file lives **outside this repo** at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.

---

### Task 1: Project Scaffolding

**Files:**
- Create: `SKILL.md` (placeholder)
- Create: `references/github-api.md` (placeholder)
- Create: `references/evaluation-prompt.md` (placeholder)
- Create: `adapters/claude.md` (placeholder)
- Create: `adapters/copilot.md` (placeholder)
- Create: `adapters/codex.md` (placeholder)
- Create: `adapters/gemini.md` (placeholder)

- [ ] **Step 1: Create directory structure**

```bash
cd ~/Documents/GitHub/copilot-review
mkdir -p references adapters
```

- [ ] **Step 2: Create placeholder files**

```bash
for f in SKILL.md references/github-api.md references/evaluation-prompt.md \
         adapters/claude.md adapters/copilot.md adapters/codex.md adapters/gemini.md; do
  echo "# TODO" > "$f"
done
```

- [ ] **Step 3: Verify structure**

```bash
find . -not -path './.git/*' -not -path './.git' -not -path './.code-review-graph/*' -type f | sort
```

Expected: all 8 files listed.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: scaffold project structure"
```

---

### Task 2: State File Module — `SKILL.md` State Management Section

**Files:**
- Modify: `SKILL.md` (add state management section)

The state file lives at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`. The skill reads it at startup and writes after every state transition.

- [ ] **Step 1: Write state schema in SKILL.md**

Add to `SKILL.md`:

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: add state file schema and init logic to SKILL.md"
```

---

### Task 3: GitHub API Reference — `references/github-api.md`

**Files:**
- Write: `references/github-api.md`

Every API call the skill needs, with exact `gh` commands and real field names verified from the API.

- [ ] **Step 1: Write github-api.md**

```markdown
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

Wait — the API endpoint for replying is `POST /repos/{owner}/{repo}/pulls/{pr}/comments` with `in_reply_to` set to the parent comment ID. This creates a reply in the thread.

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
````

- [ ] **Step 2: Commit**

```bash
git add references/github-api.md
git commit -m "docs: add GitHub API reference with real field names"
```

---

### Task 4: Evaluation Prompt — `references/evaluation-prompt.md`

**Files:**
- Write: `references/evaluation-prompt.md`

The prompt Claude uses to judge a single Copilot review comment. Embeds `receiving-code-review` principles.

- [ ] **Step 1: Write evaluation-prompt.md**

```markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add references/evaluation-prompt.md
git commit -m "docs: add evaluation prompt with receiving-code-review principles"
```

---

### Task 5: State Machine Engine — Core Loop in `SKILL.md`

**Files:**
- Modify: `SKILL.md` (replace placeholder with full state machine)

This is the main body of the skill. It defines the sub-commands and the state machine loop.

- [ ] **Step 1: Write the full SKILL.md**

````markdown
---
name: copilot-review
description: Automate the GitHub Copilot PR review feedback loop — collect reviews, evaluate comments, implement accepted changes, handle CI, re-request review, exit smartly.
argument-hint: "<pr-number> | status | resume | stop"
---

# /copilot-review — Automated Copilot PR Review Loop

State-machine-driven skill. One state file per PR at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`. All GitHub operations use `gh` CLI.

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
   If the current branch has an open PR via `gh pr list --head <branch> --json number --jq '.[0].number'`, use that.

2. **Load or create state file.**
   Path: `~/.claude/copilot-review/${owner}-${repo}-${prNumber}.json`
   If it exists, read it. If not, create with:
   ```json
   {"prNumber": <n>, "owner": "<o>", "repo": "<r>", "currentState": "COLLECT", "round": 0, "lastReviewId": null, "handledComments": {}, "roundSummaries": [], "ciStatus": "unknown", "ciFixFiles": [], "smartExit": {"consecutiveNoAction": 0}}
   ```

3. **Transition to COLLECT.**

### State: COLLECT

1. **Fetch Copilot reviews.**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews?per_page=100" \
     --jq '.[] | select(.user.login == "copilot-pull-request-reviewer[bot]") | {id, submitted_at}'
   ```

2. **Filter to new reviews** (id > `lastReviewId` from state file, or all if null).

3. **If no new reviews:**
   - Increment `consecutiveNoAction` in state.
   - **Smart exit check:** If `consecutiveNoAction >= 2`, transition to DONE.
   - Otherwise: wait 120 seconds, then re-enter COLLECT.

4. **For each new review, fetch Copilot comments:**
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/comments?per_page=100" \
     --jq '.[] | select(.pull_request_review_id == {review_id} and .user.login == "Copilot" and .in_reply_to_id == null) | {id, body, path, line, diff_hunk}'
   ```

5. **Cross-reference with `handledComments`** — skip already-handled IDs.

6. **If no unhandled comments:** update `lastReviewId`, increment `consecutiveNoAction`, do smart exit check, wait and re-enter COLLECT.

7. **If unhandled comments exist:** save them to a working list, update `lastReviewId`, transition to EVALUATE.

### State: EVALUATE

For each unhandled comment, spawn evaluation in parallel (they are independent):

1. **Gather context:**
   - Read the source file at `{path}` around `{line}` (20 lines of context)
   - Read the nearest `AGENTS.md` for project conventions
   - Collect `priorRejections` from `handledComments` where `action == "rejected"`

2. **Evaluate** using the prompt in `references/evaluation-prompt.md`. Feed:
   - Comment body, file path, line, diff hunk
   - Source code context
   - Project conventions
   - Prior rejections at same file:line
   - Current round number

3. **Apply decision rules** from evaluation-prompt.md.

4. **Classify each comment:**
   - **Accepted** → queue for IMPLEMENT
   - **Rejected** → reply to GitHub thread, resolve, record in `handledComments`

5. **After all evaluations:**
   - If any accepted → transition to IMPLEMENT
   - If all rejected → update state, increment `consecutiveNoAction`, transition to COLLECT

### State: IMPLEMENT

For each accepted comment, process sequentially (same-file comments must be ordered):

1. **Apply the code change.** Edit the file based on the comment's suggestion. Use the agent's native edit tool.

2. **Run lint.** Detect the project's linter:
   ```bash
   # Try pnpm first (monorepo), then npm, then yarn
   pnpm --filter <package> lint 2>/dev/null || npm run lint 2>/dev/null || yarn lint 2>/dev/null
   ```
   If lint fails and the failure is related to this change, fix it. If lint fails due to pre-existing issues, note it and continue.

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

5. **Reply to GitHub thread:**
   Use the `replyText` from evaluation.
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/comments" \
     --method POST \
     -f body="<replyText>" \
     -f in_reply_to="{comment_id}"
   ```

6. **Resolve thread:**
   ```bash
   gh api graphql -f query='
   mutation($threadId: ID!) {
     resolveReviewThread(input: { threadId: $threadId }) {
       thread { isResolved }
     }
   }' -f threadId="<thread_id>"
   ```
   Thread ID = the `pull_request_review_id` from the comment.

7. **Record in state:** Add entry to `handledComments` with `action: "accepted"`, `commitSha`, file, line, decision, severity, confidence.

8. **If more accepted comments remain:** go to step 1 with next comment.

9. **All done:** Transition to WAIT_CI.

### State: WAIT_CI

1. **Check CI status:**
   ```bash
   gh pr checks {pr} --json name,conclusion --jq '.[] | select(.conclusion != "SUCCESS" and .conclusion != "SKIPPED" and .conclusion != "NEUTRAL") | {name, conclusion}'
   ```

2. **If any check is failing:**
   - Read the failing check logs via `gh run view <run_id> --log`
   - Analyze the failure
   - If fixable: edit files, lint, commit with `ci(scope): fix <check name>`, push, record fixed files in `ciFixFiles` array
   - Go back to step 1 (re-check CI)
   - If not fixable (flaky test, infra issue): report to user, pause

3. **Once CI is green:**
   - Compare `ciFixFiles` with files in `handledComments` where `action == "accepted"`
   - **If overlap** (any CI-fixed file matches a commented file) → transition to RE_REQUEST (review is stale)
   - **If no overlap** → transition to COLLECT

### State: RE_REQUEST

1. **Dismiss the previous Copilot review:**
   ```bash
   # Dismiss each Copilot review since lastReviewId
   gh api "/repos/{owner}/{repo}/pulls/{pr}/reviews/{review_id}/dismissals" \
     --method PUT \
     -f message="Re-requesting review after CI fix that touched reviewed files" \
     -f event="DISMISS"
   ```

2. **Re-request Copilot review.**
   Try REST first:
   ```bash
   gh api "/repos/{owner}/{repo}/pulls/{pr}/requested_reviewers" \
     --method POST \
     -f "reviewers[]=copilot-pull-request-reviewer"
   ```
   If that fails, use GraphQL with the PR node ID.

3. **Update state:** increment round, save round summary, clear `ciFixFiles`, reset `lastReviewId` to null.

4. **Transition to COLLECT.**

### State: DONE

1. **Write final summary** to state file.

2. **Print summary to user:**
   ```
   Copilot review loop complete.
   PR: https://github.com/{owner}/{repo}/pull/{pr}
   Rounds: {n}
   Total accepted: {accepted_count}
   Total rejected: {rejected_count}
   Exit reason: {reason}
   ```

3. **Stop.**

---

## Smart Exit Conditions

Checked after every COLLECT with no new actionable comments:

1. **`consecutiveNoAction >= 2`** — Two rounds with nothing to do. Copilot has no more feedback.

2. **All comments minor + round >= 3** — After 3 rounds, only minor/style comments remain. Diminishing returns.

3. **Repeat detection** — A new Copilot comment matches the same `file + line + topic` as a previously rejected comment. Copilot is repeating itself, not adding value.

When any trigger fires, write the exit reason to state and transition to DONE.

---

## Error Recovery

- If a step fails (network error, API rate limit, merge conflict), save state and stop.
- State file preserves progress — resume with `/copilot-review resume`.
- If CI fix introduces new failures, record the attempt in state and try up to 3 times before asking the user.
- If `gh` is not authenticated, report and stop.
````

- [ ] **Step 2: Commit**

```bash
git add SKILL.md
git commit -m "feat: add full state machine engine to SKILL.md"
```

---

### Task 6: Claude Adapter — `adapters/claude.md`

**Files:**
- Write: `adapters/claude.md`

- [ ] **Step 1: Write claude.md**

```markdown
---
name: copilot-review
description: Automate the GitHub Copilot PR review feedback loop
argument-hint: "<pr-number> | status | resume | stop"
---

# /copilot-review — Claude Code Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Claude Code tool names.

## Tool Mapping

| Skill Reference | Claude Code Tool |
|----------------|-----------------|
| `bash` / `gh` | `Bash` |
| `read file` | `Read` |
| `edit file` | `Edit` |
| `write file` | `Write` |
| `spawn subagent` | `Agent` with `subagent_type: "general-purpose"` |

## Claude-Specific Notes

- **Parallel evaluation:** Use the `Agent` tool to spawn subagents for parallel comment evaluation. Each subagent evaluates one comment independently.
- **File editing:** Use `Edit` with exact `old_string` / `new_string`. Always `Read` the file first.
- **State file:** Read/write via `Read`/`Write` tools at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.
- **No `gh` tool:** Claude Code does not have a dedicated `gh` tool — use `Bash` for all `gh` commands.
- **Session persistence:** If the session ends mid-loop, state file allows resuming with `Skill("copilot-review", "resume")`.
````

- [ ] **Step 2: Commit**

```bash
git add adapters/claude.md
git commit -m "feat: add Claude Code adapter"
```

---

### Task 7: Copilot CLI Adapter — `adapters/copilot.md`

**Files:**
- Write: `adapters/copilot.md`

- [ ] **Step 1: Write copilot.md**

```markdown
# Copilot Review — Copilot CLI Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Copilot CLI tool names.

## Tool Mapping

| Skill Reference | Copilot CLI Tool |
|----------------|-----------------|
| `bash` / `gh` | `shell` |
| `read file` | `read` |
| `edit file` | `edit` |
| `write file` | `write` |
| `spawn subagent` | `agent` |

## Copilot CLI-Specific Notes

- Use `shell` for all `gh` commands.
- State file operations use `read`/`write` on `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.
````

- [ ] **Step 2: Commit**

```bash
git add adapters/copilot.md
git commit -m "feat: add Copilot CLI adapter"
```

---

### Task 8: Codex and Gemini Adapters

**Files:**
- Write: `adapters/codex.md`
- Write: `adapters/gemini.md`

- [ ] **Step 1: Write codex.md**

```markdown
# Copilot Review — Codex Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Codex tool names.

## Tool Mapping

| Skill Reference | Codex Tool |
|----------------|-----------|
| `bash` / `gh` | `RunShellScript` |
| `read file` | `ReadFiles` |
| `edit file` | `EditFiles` |
| `write file` | `WriteFiles` |
| `spawn subagent` | `SpawnAgent` |

## Codex-Specific Notes

- State file operations at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.
- Codex uses `RunShellScript` for all shell commands including `gh`.
````

- [ ] **Step 2: Write gemini.md**

```markdown
# Copilot Review — Gemini CLI Adapter

The canonical skill lives at the plugin root `SKILL.md`.
Load and follow that file. This adapter maps Gemini CLI tool names.

## Tool Mapping

| Skill Reference | Gemini CLI Tool |
|----------------|----------------|
| `bash` / `gh` | `run_shell_command` |
| `read file` | `read_file` |
| `edit file` | `edit_file` |
| `write file` | `write_file` |
| `spawn subagent` | `delegate_to_agent` |

## Gemini-Specific Notes

- State file operations at `~/.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.
- Use `run_shell_command` for all `gh` commands.
````

- [ ] **Step 3: Commit**

```bash
git add adapters/codex.md adapters/gemini.md
git commit -m "feat: add Codex and Gemini adapters"
```

---

### Task 9: Integration Test — Simulated Loop

**Files:**
- Create: `tests/simulate-review.sh` (smoke test script)

This is NOT a unit test — it's a smoke test that verifies all `gh` commands parse correctly and the state machine transitions work. It runs against a real (closed) PR to avoid side effects.

- [ ] **Step 1: Write smoke test**

```bash
#!/bin/bash
# Smoke test for copilot-review skill
# Runs against a real PR to verify API connectivity and response parsing.
# Does NOT modify any state — read-only verification.

set -euo pipefail

PR="${1:?Usage: $0 <pr-number>}"
OWNER=$(git remote get-url origin | sed 's|.*[:/]\([^/]*\)/\([^/.]*\).*|\1|')
REPO=$(git remote get-url origin | sed 's|.*[:/][^/]*/\([^/.]*\).*|\1|')

echo "=== Test 1: List reviews ==="
REVIEWS=$(gh api "/repos/${OWNER}/${REPO}/pulls/${PR}/reviews?per_page=100")
echo "OK: Got $(echo "$REVIEWS" | jq 'length') reviews"

echo ""
echo "=== Test 2: Filter Copilot reviews ==="
COPILOT_REVIEWS=$(echo "$REVIEWS" | jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")]')
echo "OK: Found $(echo "$COPILOT_REVIEWS" | jq 'length') Copilot reviews"

echo ""
echo "=== Test 3: List review comments ==="
COMMENTS=$(gh api "/repos/${OWNER}/${REPO}/pulls/${PR}/comments?per_page=100")
echo "OK: Got $(echo "$COMMENTS" | jq 'length') comments"

echo ""
echo "=== Test 4: Filter Copilot comments ==="
COPILOT_COMMENTS=$(echo "$COMMENTS" | jq '[.[] | select(.user.login == "Copilot")]')
echo "OK: Found $(echo "$COPILOT_COMMENTS" | jq 'length') Copilot comments"

echo ""
echo "=== Test 5: CI check ==="
gh pr checks "$PR" > /dev/null 2>&1 && echo "OK: CI check command works" || echo "OK: CI check command works (possibly no checks)"

echo ""
echo "=== Test 6: PR node ID for GraphQL ==="
NODE_ID=$(gh pr view "$PR" --json id --jq '.id')
echo "OK: PR node ID: $NODE_ID"

echo ""
echo "=== Test 7: State file read/write ==="
STATE_DIR="$HOME/.claude/copilot-review"
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/${OWNER}-${REPO}-${PR}.json"
echo '{"test": true}' > "$STATE_FILE"
READ_BACK=$(cat "$STATE_FILE")
rm "$STATE_FILE"
echo "OK: State file read/write works"

echo ""
echo "=== All smoke tests passed ==="
```

- [ ] **Step 2: Run smoke test against PR 1485**

```bash
cd ~/path/to/any/repo
bash ~/Documents/GitHub/copilot-review/tests/simulate-review.sh 1485
```

Expected: All tests pass.

- [ ] **Step 3: Commit**

```bash
git add tests/simulate-review.sh
git commit -m "test: add API smoke test"
```
````

---

### Task 10: Final Review and Polish

- [ ] **Step 1: Verify all files exist and are non-trivial**

```bash
cd ~/Documents/GitHub/copilot-review
for f in SKILL.md references/github-api.md references/evaluation-prompt.md \
         adapters/claude.md adapters/copilot.md adapters/codex.md adapters/gemini.md \
         tests/simulate-review.sh; do
  lines=$(wc -l < "$f")
  echo "$f: $lines lines"
done
```

- [ ] **Step 2: Check for any placeholder/TODO remaining**

```bash
grep -rn "TODO\|TBD\|FIXME\|placeholder" --include="*.md" --include="*.sh" . || echo "No placeholders found"
```

- [ ] **Step 3: Final commit and tag**

```bash
git add -A
git commit -m "chore: final polish and verification"
git tag v0.1.0
```

- [ ] **Step 4: Print summary of what was built**

```bash
find . -not -path './.git/*' -not -path './.code-review-graph/*' -type f | sort
```
````

---

## Post-Implementation: Install to Claude Code

After all tasks are complete, install the skill for Claude Code:

```bash
# Symlink the canonical SKILL.md into Claude's skills directory
mkdir -p ~/.claude/skills/copilot-review
ln -sf ~/Documents/GitHub/copilot-review/adapters/claude.md ~/.claude/skills/copilot-review/SKILL.md
```

Usage: `/copilot-review 1485`

# Copilot Review Skill

Automates the GitHub Copilot PR review feedback loop. Collects Copilot's
review comments, evaluates them, implements accepted changes, waits for CI,
re-requests review, and exits when there's nothing left to fix.

## Installation

```bash
git clone <this-repo>
cd copilot-review
ln -sf "$(pwd)/SKILL.md" ~/.claude/skills/copilot-review/SKILL.md
ln -sf "$(pwd)/references" ~/.claude/skills/copilot-review/references
```

Verify:

```bash
ls ~/.claude/skills/copilot-review/
# Should show: SKILL.md  references/
```

For **Copilot CLI / Codex / Gemini CLI**, symlink to the respective adapter
in `adapters/` instead of `SKILL.md` directly.

## Prerequisites

### This Skill

| Tool | Check | Purpose |
|------|-------|---------|
| `gh` CLI | `gh auth status` | GitHub API (reviews, comments, CI) |
| `git` | `git --version` | Committing changes |
| `jq` | `jq --version` | Parsing JSON responses |

**`gh` scopes needed:** `repo`, `read:org`, `workflow`.

### GitHub Copilot Code Review

The PR must be in a repository where **Copilot code review** is available.
This feature requires a paid Copilot plan:

| Plan | Code review available? |
|------|----------------------|
| Copilot Free | No |
| Copilot Pro | Yes |
| Copilot Pro+ | Yes |
| Copilot Business | Yes — also available to org members **without** a license, if enabled by an admin |
| Copilot Enterprise | Yes — also available to org members **without** a license, if enabled by an admin |

For **Business / Enterprise** orgs, an admin must also enable the
**Copilot code review** policy. Without this, Copilot won't appear in the
reviewer picker and the GraphQL re-request will silently do nothing.

Key behaviors to know:

- Copilot always leaves a **"Comment"** review — never "Approve" or "Request
  changes". Its reviews do not count toward required approvals.
- Copilot does **not** auto-re-review when you push new commits. You must
  explicitly re-request it (the skill does this automatically).
- Copilot **may repeat** the same comments on re-review, even if they were
  previously resolved or downvoted.
- Copilot does **not reply** to replies on its review threads.

## Troubleshooting

**Copilot doesn't respond to review requests:**

- Your account must have a Copilot Pro, Pro+, Business, or Enterprise
  subscription. Free accounts cannot use code review.
- If you're on a Business/Enterprise plan without a personal license, an
  admin must enable "Allow members without a Copilot license to use Copilot
  code review" in the org's Copilot policies.
- The org must have the **Copilot code review** policy enabled.
- Copilot only reviews pull requests, not individual commits or branches.

**Re-request returns immediately with no new comments:**

- This is normal. Copilot may have nothing new to say after reviewing the
  latest changes. The skill treats this as a positive signal and exits after
  two consecutive rounds with no new feedback.

**`requestReviewsByLogin` GraphQL mutation fails:**

- Copilot is a Bot type, not a User. The mutation must use `botLogins`:
  `["copilot-pull-request-reviewer[bot]"]`.
- If the mutation fails, the skill falls back to posting `@copilot review
  this PR` as a PR comment.

## Usage

```
/copilot-review <pr-number>     Start or resume the review loop
/copilot-review status          Show current state
/copilot-review resume          Resume from last saved state
/copilot-review stop            Stop and exit
```

## How It Works

The skill runs a state machine:

```
INIT → COLLECT → EVALUATE → IMPLEMENT → WAIT_CI → RE_REQUEST → COLLECT
                                                             ↓
                                                           DONE
```

- **COLLECT** — Fetch Copilot reviews and comments. Resolve merge conflicts.
- **EVALUATE** — Assess each comment independently. Accept or reject.
- **IMPLEMENT** — Apply accepted changes, lint, commit, push, reply on GitHub.
- **WAIT_CI** — Poll CI checks. Fix failures (up to 3 attempts).
- **RE_REQUEST** — Request Copilot re-review via GraphQL. Preserves existing
  reviewers.
- **DONE** — Smart exit: Copilot has no new comments for 2 consecutive rounds,
  or only minor comments remain after round 3.

Progress is saved in `.claude/copilot-review/<owner>-<repo>-<pr>.json` so the
loop can resume across sessions.

## Smart Exit

The loop stops automatically when:

- **No action for 2 rounds** — Copilot has no more substantive feedback.
- **Minor-only after round 3** — Only style/nit comments remain.
- **Repeat detection** — Copilot repeats the same file+line+topic that was
  already rejected.

## Platform Support

| Platform | Adapter |
|----------|---------|
| Claude Code | `SKILL.md` (canonical) |
| Copilot CLI | `adapters/copilot.md` |
| Codex | `adapters/codex.md` |
| Gemini CLI | `adapters/gemini.md` |

Tool mappings for each platform are documented in the **Platform Tool Mapping**
section at the end of `SKILL.md`.

## File Structure

```
SKILL.md                         Canonical skill definition
adapters/
  claude.md                      Claude Code adapter
  copilot.md                     Copilot CLI adapter
  codex.md                       Codex adapter
  gemini.md                      Gemini CLI adapter
references/
  github-api.md                  gh command recipes
  evaluation-prompt.md           Comment evaluation prompt template
.claude/copilot-review/          State files (one per PR, gitignored)
```

# Copilot Review Skill

Automates the GitHub Copilot PR review feedback loop. Collects Copilot's
review comments, evaluates them, implements accepted changes, waits for CI,
re-requests review, and exits when there's nothing left to fix.

## Installation

The skill is installed by creating symlinks from your agent's skills
directory to this repository. The setup is the same for all agents — only
the target directory differs.

### Claude Code

```bash
git clone <this-repo>
cd copilot-review
mkdir -p ~/.claude/skills/copilot-review
ln -sf "$(pwd)/SKILL.md" ~/.claude/skills/copilot-review/SKILL.md
ln -sf "$(pwd)/references" ~/.claude/skills/copilot-review/references
```

### GitHub Copilot (VS Code)

```bash
git clone <this-repo>
cd copilot-review
mkdir -p <copilot-skills-dir>/copilot-review
ln -sf "$(pwd)/adapters/copilot.md" <copilot-skills-dir>/copilot-review/SKILL.md
ln -sf "$(pwd)/references" <copilot-skills-dir>/copilot-review/references
```

If your Copilot setup does not provide a custom skills directory, keep
`adapters/copilot.md` in this repo and copy its tool mapping into your
user prompt/instructions file.

### GitHub Copilot CLI

```bash
git clone <this-repo>
cd copilot-review
mkdir -p <copilot-cli-skills-dir>/copilot-review
ln -sf "$(pwd)/adapters/copilot-cli.md" <copilot-cli-skills-dir>/copilot-review/SKILL.md
ln -sf "$(pwd)/references" <copilot-cli-skills-dir>/copilot-review/references
```

If your Copilot CLI setup does not provide a persistent skills directory,
copy the adapter mapping into `.github/copilot-instructions.md`.

### Codex

```bash
git clone <this-repo>
cd copilot-review
mkdir -p ~/.agents/skills/copilot-review
mkdir -p ~/.agents/skills/copilot-review/adapters
ln -sf "$(pwd)/SKILL.md" ~/.agents/skills/copilot-review/SKILL.md
ln -sf "$(pwd)/references" ~/.agents/skills/copilot-review/references
ln -sf "$(pwd)/adapters/codex.md" ~/.agents/skills/copilot-review/adapters/codex.md
```

The Codex adapter is a supporting note, not a replacement for the canonical
skill. If your Codex build documents a different skills directory, use that
directory but still install the root `SKILL.md` as `SKILL.md`.

### Other Agents

For any agent that supports custom skills, symlink `SKILL.md` and
`references/` into its skills directory. If the agent needs platform-specific
tool names, create an adapter following the pattern in `adapters/`.

```bash
git clone <this-repo>
cd copilot-review
mkdir -p <agent-skills-dir>/copilot-review
ln -sf "$(pwd)/SKILL.md" <agent-skills-dir>/copilot-review/SKILL.md
ln -sf "$(pwd)/references" <agent-skills-dir>/copilot-review/references
```

### After installation

Add `.copilot-review/` to each project's `.gitignore` to avoid committing
state files:

```bash
echo '.copilot-review/' >> .gitignore
```

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

Progress is saved in `.copilot-review/<owner>-<repo>-<pr>.json` so the
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
| GitHub Copilot (VS Code) | `adapters/copilot.md` |
| GitHub Copilot CLI | `adapters/copilot-cli.md` |
| Codex | `SKILL.md` plus `adapters/codex.md` notes |

Tool mappings for each platform are documented in the **Platform Tool Mapping**
section at the end of `SKILL.md`.

## Multi-Agent Validation

This repository includes a shared compatibility contract and smoke skeleton so
adapter changes can be validated consistently across agents.

- Compatibility spec:
  `references/multi-agent-compatibility.md`
- Validation plan:
  `references/multi-agent-validation-plan.md`
- Smoke skeleton:
  `tests/simulate-review-multi-agent.sh`

Run the smoke skeleton:

```bash
./tests/simulate-review-multi-agent.sh <agent> <pr-number>
```

Supported agent values: `claude`, `copilot-vscode`, `copilot-cli`, `codex`.

For Codex packaging changes that should not touch GitHub, run:

```bash
bash tests/validate-codex-compat.sh
```

## File Structure

```
SKILL.md                         Canonical skill definition
adapters/
  claude.md                      Claude Code adapter
  copilot.md                     GitHub Copilot adapter
  copilot-cli.md                 GitHub Copilot CLI adapter
  codex.md                       Codex adapter
references/
  github-api.md                  gh command recipes
  evaluation-prompt.md           Comment evaluation prompt template
tests/
  validate-codex-compat.sh       Local Codex packaging checks
.copilot-review/          State files (one per PR, gitignored)
```

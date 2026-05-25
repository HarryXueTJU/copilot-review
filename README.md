# Copilot Review Skill

Automates the GitHub Copilot PR review feedback loop. Collects Copilot's
review comments, evaluates them, implements accepted changes, waits for CI,
re-requests review, and exits when there's nothing left to fix.

## Installation

```bash
git clone <this-repo>
ln -sf "$(pwd)/copilot-review/SKILL.md" ~/.claude/skills/copilot-review/SKILL.md
ln -sf "$(pwd)/copilot-review/references" ~/.claude/skills/copilot-review/references
```

Verify:

```bash
ls ~/.claude/skills/copilot-review/
# Should show: SKILL.md  references/
```

For **Copilot CLI / Codex / Gemini CLI**, symlink to the respective adapter
in `adapters/` instead of `SKILL.md` directly.

## Prerequisites

| Tool | Check | Purpose |
|------|-------|---------|
| `gh` CLI | `gh auth status` | GitHub API (reviews, comments, CI) |
| `git` | `git --version` | Committing changes |
| `jq` | `jq --version` | Parsing JSON responses |

**`gh` scopes needed:** `repo`, `read:org`, `workflow`.

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

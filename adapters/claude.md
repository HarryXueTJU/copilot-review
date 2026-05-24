---
name: copilot-review
description: Automate the GitHub Copilot PR review feedback loop
argument-hint: "<pr-number> | status | resume | stop"
---

# /copilot-review — Claude Code Adapter

The canonical skill lives at `../SKILL.md` (one directory up from this adapter).
Load and follow that file along with its `references/` directory.
This adapter maps Claude Code tool names and provides Claude-specific notes.

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

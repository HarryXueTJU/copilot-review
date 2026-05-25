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
- State file operations use `read`/`write` on `.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.

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

- State file operations at `.claude/copilot-review/<owner>-<repo>-<prNumber>.json`.
- Codex uses `RunShellScript` for all shell commands including `gh`.

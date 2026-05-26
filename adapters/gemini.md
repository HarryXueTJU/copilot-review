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

- State file operations at `.copilot-review/<owner>-<repo>-<prNumber>.json`.
- Use `run_shell_command` for all `gh` commands.
